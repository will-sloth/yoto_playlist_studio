import SwiftUI

struct MoveTracksSheet: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    let selected: Set<String>
    let source: JSON
    @State private var destinationID = ""
    @State private var working = false
    @State private var failure: String?
    @State private var message = ""
    private var destinations: [Playlist] {
        studio.playlists.filter { $0.id != source["cardId"] as? String && studio.newPlaylists[$0.id] == nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(studio.pendingMove == nil ? "Move tracks to playlist" : "Finish moving tracks").font(.title2.bold())
            let original = studio.pendingMove?.plan.source ?? source
            let ids = studio.pendingMove == nil ? selected : Set<String>()
            Text("From: \(original["title"] as? String ?? "Playlist")").font(.callout)
            if let move = studio.pendingMove {
                Text("\(move.plan.count) track(s) → \(move.plan.destination["title"] as? String ?? "Playlist")")
                Text("Retry checks both playlists first. Tracks already copied will not be copied again.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(CardEditor.rows(source).filter { ids.contains($0.id) }) { Text($0.title).font(.callout) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 160)
                Picker("Destination", selection: $destinationID) {
                    Text("Choose playlist…").tag("")
                    ForEach(destinations) { Text($0.title).tag($0.id) }
                }
                if destinations.isEmpty { Text("Create and save another playlist first.").font(.caption) }
                Text("Tracks are added at the end in their current order, including audio and artwork. The app confirms the destination copy before removing originals. No audio download or upload is needed.").font(.caption).foregroundStyle(.secondary)
            }
            if working { HStack { ProgressView().controlSize(.small); Text(message).font(.callout) } }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Close") { dismiss() }.disabled(working)
                if studio.pendingMove != nil && !working {
                    Button("Stop moving") {
                        studio.pendingMove = nil
                        studio.status = "Move stopped. Refresh both playlists to see saved copies; original removal may be incomplete."
                        dismiss()
                    }
                }
                Spacer()
                Button(studio.pendingMove == nil ? "Move tracks" : "Retry move") { move() }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || (studio.pendingMove == nil && destinationID.isEmpty))
            }
            if studio.pendingMove != nil { Text("Closing keeps this move available to resume. Stop moving keeps the playlists as they are.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(26).frame(width: 540)
        .interactiveDismissDisabled(working)
    }
    private func move() {
        working = true; failure = nil
        Task { @MainActor in
            defer { working = false }
            do {
                if studio.pendingMove == nil {
                    message = "Checking playlists and saving a backup…"
                    let freshSource = try await studio.api.card(source["cardId"] as! String)
                    guard try PlaylistMovePlan.same(freshSource, source) else { throw StudioError("The original playlist changed. Close and reload before moving tracks.") }
                    let target = try await studio.api.card(destinationID)
                    let plan = try PlaylistMovePlan(source: freshSource, destination: target, selected: selected)
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("YotoPixelStudio/Backups", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try JSONSerialization.data(withJSONObject: ["source": freshSource, "destination": target], options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("move-" + UUID().uuidString + ".json"), options: .atomic)
                    studio.pendingMove = PlaylistMover(plan: plan)
                }
                guard let mover = studio.pendingMove else { return }
                let saved = try await mover.perform(service: studio.api) { message = $0 }
                if studio.selectedPlaylist == saved["cardId"] as? String {
                    studio.card = saved; studio.selectedTracks = []; studio.suggestions = [:]; studio.rejected = [:]
                    await studio.loadExistingIcons()
                }
                studio.status = "Moved \(mover.plan.count) track(s) with artwork to \(mover.plan.destination["title"] as? String ?? "playlist")."
                studio.pendingMove = nil
                dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
}
