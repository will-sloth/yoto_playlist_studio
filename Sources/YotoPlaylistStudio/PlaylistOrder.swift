import Foundation

enum PlaylistOrder {
    static func sameContent(_ lhs: JSON, _ rhs: JSON) throws -> Bool {
        try JSONSerialization.data(withJSONObject: lhs["content"] ?? [:], options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: rhs["content"] ?? [:], options: [.sortedKeys])
    }
    static func payload(_ card: JSON, order: [String]) throws -> JSON {
        let rows = CardEditor.rows(card)
        guard order.count == rows.count, Set(order).count == order.count, Set(order) == Set(rows.map(\.id)),
              let original = (card["content"] as? JSON)?["chapters"] as? [JSON] else {
            throw StudioError("The track list changed. Reload the latest order before saving.")
        }
        if order == rows.map(\.id) { return try CardEditor.applying([:], to: card) }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let oldPositions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        // Keep adjacent tracks from the same chapter together. If a chapter is
        // split, clone its settings/artwork for each run, with distinct short keys.
        var groups: [(chapter: Int, ids: [String])] = []
        for id in order {
            let ci = byID[id]!.chapter
            if groups.last?.chapter == ci { groups[groups.count - 1].ids.append(id) }
            else { groups.append((ci, [id])) }
        }
        var used = Set<Int>(), keys = Set(original.compactMap { $0["key"] as? String })
        var position = 0
        var chapters: [JSON] = groups.enumerated().map { groupIndex, group in
            var chapter = original[group.chapter]
            if !used.insert(group.chapter).inserted {
                var key: String
                repeat { key = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)) } while keys.contains(key)
                keys.insert(key); chapter["key"] = key
            }
            let originalTracks = original[group.chapter]["tracks"] as? [JSON] ?? []
            let tracks: [JSON] = group.ids.map { id in
                var track = originalTracks[byID[id]!.track]
                if track["overlayLabel"] as? String == String(oldPositions[id]! + 1) { track["overlayLabel"] = String(position + 1) }
                position += 1
                return track
            }
            chapter["tracks"] = tracks
            if chapter["overlayLabel"] as? String == String(group.chapter + 1) { chapter["overlayLabel"] = String(groupIndex + 1) }
            if tracks.count != originalTracks.count {
                for field in ["duration", "fileSize"] {
                    let values = tracks.compactMap { ($0[field] as? NSNumber)?.doubleValue }
                    chapter[field] = values.count == tracks.count ? values.reduce(0, +) : nil
                }
            }
            return chapter
        }
        // Empty chapters carry no draggable audio; retain their settings as well.
        chapters += original.filter { ($0["tracks"] as? [JSON] ?? []).isEmpty }
        var result = try CardEditor.applying([:], to: card)
        var content = result["content"] as! JSON
        content["chapters"] = chapters; result["content"] = content
        return result
    }
}
