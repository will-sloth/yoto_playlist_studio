import SwiftUI
import UniformTypeIdentifiers

struct ReorderTracksSheet: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    let source: JSON
    @State private var order: [String] = []
    @State private var baseline: JSON = [:]
    @State private var dragging: String?
    private let dragType = UTType(exportedAs: "local.yotoplayliststudio.track-order")
    @State private var working = false
    @State private var failure: String?
    @State private var message = ""
    private var rows: [TrackRow] { CardEditor.rows(baseline) }
    private var changed: Bool { order != rows.map(\.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reorder tracks").font(.title2.bold())
            Text(baseline["title"] as? String ?? "Playlist").font(.callout).foregroundStyle(.secondary)
            Text("Drag a track onto another to move it, or use the arrows. Changes stay local until you choose Save order.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                ForEach(order, id: \.self) { id in
                    if let row = rows.first(where: { $0.id == id }), let index = order.firstIndex(of: id) {
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                            Text(row.title).lineLimit(2)
                            Spacer()
                            Button { move(id, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move up").accessibilityLabel("Move \(row.title) up")
                            Button { move(id, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == order.count - 1).help("Move down").accessibilityLabel("Move \(row.title) down")
                        }.padding(10).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8).contentShape(Rectangle())
                        .onDrag {
                            dragging = id
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: dragType.identifier, visibility: .ownProcess) { completion in
                                completion(Data(id.utf8), nil); return nil
                            }
                            return provider
                        }
                        .onDrop(of: [dragType], delegate: TrackOrderDrop(target: id, type: dragType, order: $order, dragging: $dragging, enabled: !working))
                    }
                }
                }.padding(4)
            }.frame(height: 340).disabled(working)
            if working { HStack { ProgressView().controlSize(.small); Text(message).font(.caption) } }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.disabled(working)
                Button("Reset order") { order = rows.map(\.id); failure = nil }.disabled(working || !changed)
                if failure != nil && !studio.demo { Button("Reload latest order") { reload() }.disabled(working) }
                Spacer()
                Button("Save order") { save() }.buttonStyle(.borderedProminent).disabled(working || !changed)
            }
        }.padding(26).frame(width: 600)
        .onAppear { baseline = source; order = CardEditor.rows(source).map(\.id) }
        .interactiveDismissDisabled(working)
    }
    private func move(_ id: String, by delta: Int) {
        guard let from = order.firstIndex(of: id), order.indices.contains(from + delta) else { return }
        order.swapAt(from, from + delta); failure = nil
    }
    private func save() {
        working = true; failure = nil; message = "Saving track order…"
        Task { @MainActor in
            defer { working = false }
            do {
                let result: JSON
                if studio.demo {
                    result = try PlaylistOrder.payload(baseline, order: order)
                    let oldRows = rows, newRows = CardEditor.rows(result)
                    var art: [String: ArtChoice] = [:]
                    for (index, id) in order.enumerated() where oldRows.contains(where: { $0.id == id }) {
                        if let choice = studio.demoArt[id] { art[newRows[index].id] = choice }
                    }
                    studio.demoArt = art
                } else {
                    result = try await studio.api.saveOrder(order, baseline: baseline) { latest in
                        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("YotoPixelStudio/Backups", isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("reorder-" + UUID().uuidString + ".json"), options: .atomic)
                    }
                }
                studio.card = result; studio.selectedTracks = []; studio.suggestions = [:]; studio.rejected = [:]
                studio.status = studio.demo ? "Demo track order saved locally." : "Track order saved to Yoto."
                dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
    private func reload() {
        working = true; message = "Loading latest order…"
        Task { @MainActor in
            defer { working = false }
            do {
                guard let id = baseline["cardId"] as? String else { return }
                let fresh = try await studio.api.card(id)
                baseline = fresh; order = CardEditor.rows(fresh).map(\.id)
                studio.card = fresh; studio.selectedTracks = []; studio.suggestions = [:]; studio.rejected = [:]
                failure = nil
            } catch { failure = error.localizedDescription }
        }
    }
}

private struct TrackOrderDrop: DropDelegate {
    let target: String
    let type: UTType
    @Binding var order: [String]
    @Binding var dragging: String?
    let enabled: Bool
    func validateDrop(info: DropInfo) -> Bool {
        enabled && dragging != nil && info.hasItemsConforming(to: [type])
    }
    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info), let id = dragging,
              let from = order.firstIndex(of: id), let to = order.firstIndex(of: target), from != to else { return }
        withAnimation { order.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: enabled ? .move : .cancel) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        dragging = nil; return true
    }
}
