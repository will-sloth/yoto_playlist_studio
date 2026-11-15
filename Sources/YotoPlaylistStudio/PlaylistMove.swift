import Foundation

struct PlaylistMovePlan {
    let source: JSON
    let destination: JSON
    let sourceAfter: JSON
    let destinationAfter: JSON
    let addedChapters: [JSON]
    let count: Int

    static func same(_ lhs: JSON, _ rhs: JSON) throws -> Bool {
        func bytes(_ card: JSON) throws -> Data {
            var fields: JSON = [:]
            for key in ["cardId", "title", "content", "metadata"] { if let value = card[key] { fields[key] = value } }
            return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        }
        return try bytes(lhs) == bytes(rhs)
    }
    static func payload(_ card: JSON, chapters: [JSON]) throws -> JSON {
        var result = try CardEditor.applying([:], to: card)
        var content = result["content"] as! JSON
        content["chapters"] = chapters
        result["content"] = content
        // Recalculate only media aggregates we can derive; never keep stale totals.
        if var metadata = result["metadata"] as? JSON, var media = metadata["media"] as? JSON {
            let tracks = chapters.flatMap { $0["tracks"] as? [JSON] ?? [] }
            for key in ["duration", "fileSize"] {
                let values = tracks.compactMap { ($0[key] as? NSNumber)?.doubleValue }
                if values.count == tracks.count { media[key] = values.reduce(0, +) }
                else { media.removeValue(forKey: key) }
            }
            media.removeValue(forKey: "readableFileSize")
            metadata["media"] = media; result["metadata"] = metadata
        }
        return result
    }
    init(source: JSON, destination: JSON, selected: Set<String>) throws {
        guard let sourceID = source["cardId"] as? String, let destinationID = destination["cardId"] as? String,
              sourceID != destinationID, !sourceID.isEmpty, !destinationID.isEmpty,
              !selected.isEmpty, selected.isSubset(of: Set(CardEditor.rows(source).map(\.id))),
              let original = (source["content"] as? JSON)?["chapters"] as? [JSON],
              var target = (destination["content"] as? JSON)?["chapters"] as? [JSON] else {
            throw StudioError("Choose tracks and a different saved playlist. Reload if the track list changed.")
        }
        var kept: [JSON] = [], added: [JSON] = []
        var keys = Set(target.compactMap { $0["key"] as? String })
        for (ci, chapter) in original.enumerated() {
            let tracks = chapter["tracks"] as? [JSON] ?? []
            var remaining: [JSON] = []
            for (ti, originalTrack) in tracks.enumerated() {
                guard selected.contains("\(ci):\(ti)") else { remaining.append(originalTrack); continue }
                guard let audio = originalTrack["trackUrl"] as? String, !audio.isEmpty else { throw StudioError("This track has no reusable audio reference.") }
                var moved = chapter, track = originalTrack
                var key: String
                repeat { key = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)) } while keys.contains(key)
                keys.insert(key)
                moved["key"] = key
                moved["title"] = originalTrack["title"] ?? chapter["title"] ?? "Track"
                let label = String(target.count + added.count + 1)
                moved["overlayLabel"] = label; track["overlayLabel"] = label
                // Keep inherited chapter artwork/ambient settings and explicit track overrides.
                moved["tracks"] = [track]
                for field in ["duration", "fileSize"] {
                    moved[field] = originalTrack[field]
                }
                added.append(moved)
            }
            if !remaining.isEmpty || tracks.isEmpty {
                var updated = chapter; updated["tracks"] = remaining
                if remaining.count != tracks.count {
                    for field in ["duration", "fileSize"] {
                        let values = remaining.compactMap { ($0[field] as? NSNumber)?.doubleValue }
                        updated[field] = values.count == remaining.count ? values.reduce(0, +) : nil
                    }
                }
                kept.append(updated)
            }
        }
        target += added
        self.source = source; self.destination = destination
        self.sourceAfter = try Self.payload(source, chapters: kept)
        self.destinationAfter = try Self.payload(destination, chapters: target)
        self.addedChapters = added; self.count = added.count
    }
    func destinationContainsCopies(_ card: JSON) throws -> Bool {
        let chapters = (card["content"] as? JSON)?["chapters"] as? [JSON] ?? []
        return try addedChapters.allSatisfy { expected in
            guard let actual = chapters.first(where: { $0["key"] as? String == expected["key"] as? String }) else { return false }
            return try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        }
    }
}

@MainActor
final class PlaylistMover {
    let plan: PlaylistMovePlan
    private(set) var copyConfirmed = false
    init(plan: PlaylistMovePlan) { self.plan = plan }
    func perform(service: YotoService, progress: (String) -> Void) async throws -> JSON {
        let sourceID = plan.source["cardId"] as! String, destinationID = plan.destination["cardId"] as! String
        do {
            progress("Checking both playlists…")
            let source = try await service.card(sourceID)
            let destination = try await service.card(destinationID)
            copyConfirmed = try plan.destinationContainsCopies(destination)
            // Reconcile a source save whose response was lost; never append copies twice.
            if copyConfirmed, try PlaylistMovePlan.same(source, plan.sourceAfter) { return source }
            guard try PlaylistMovePlan.same(source, plan.source) else { throw StudioError("The original playlist changed. No further changes were sent.") }
            if !copyConfirmed {
                guard try PlaylistMovePlan.same(destination, plan.destination) else { throw StudioError("The destination playlist changed. No further changes were sent.") }
                progress("Saving tracks and artwork in the destination…")
                _ = try await service.save(plan.destinationAfter)
            }
            progress("Confirming the destination copy…")
            let confirmed = try await service.card(destinationID)
            guard try plan.destinationContainsCopies(confirmed) else { throw StudioError("The destination copy could not be confirmed. Original tracks are kept.") }
            copyConfirmed = true
            let latestSource = try await service.card(sourceID)
            guard try PlaylistMovePlan.same(latestSource, plan.source) else { throw StudioError("The original playlist changed during the move. Original tracks were not removed.") }
            progress("Removing tracks from the original playlist…")
            _ = try await service.save(plan.sourceAfter)
            let result = try await service.card(sourceID)
            guard try PlaylistMovePlan.same(result, plan.sourceAfter) else { throw StudioError("Could not confirm removal. Retry to check the playlists before doing anything else.") }
            return result
        } catch {
            let state = copyConfirmed ? "The destination copy is confirmed. Retry to finish removal without copying again." : "Original tracks have not been removed. Retry checks for existing copies before continuing."
            throw StudioError(error.localizedDescription + "\n" + state)
        }
    }
}
