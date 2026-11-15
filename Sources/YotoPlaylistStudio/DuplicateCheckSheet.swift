import SwiftUI

struct DuplicateCheckSheet: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    let source: JSON
    @State private var snapshot: JSON = [:]
    @State private var loading = true
    @State private var failure: String?
    private var groups: [PlaylistDuplicateGroup] { PlaylistDuplicates.groups(snapshot) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check duplicates").font(.title2.bold())
            Text(snapshot["title"] as? String ?? source["title"] as? String ?? "Playlist").font(.callout).foregroundStyle(.secondary)
            if loading { HStack { ProgressView().controlSize(.small); Text("Checking playlist…") } }
            else if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            else if groups.isEmpty {
                Label("No duplicates found", systemImage: "checkmark.circle").font(.headline).foregroundStyle(.green)
                Text("No repeated audio references or matching titles were found.").font(.callout).foregroundStyle(.secondary)
            } else {
                let exact = groups.filter { $0.kind == .audio }.count
                let possible = groups.filter { $0.kind == .title }.count
                Text("\(exact) repeated audio group(s) · \(possible) matching-title group(s)").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(group.kind == .audio ? "Same audio" : "Matching title — review", systemImage: group.kind == .audio ? "waveform" : "text.magnifyingglass").font(.headline)
                                ForEach(group.tracks) { row in
                                    let position = (CardEditor.rows(snapshot).firstIndex { $0.id == row.id } ?? 0) + 1
                                    HStack(alignment: .top) {
                                        Text("Track \(position)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
                                        Text(row.title).font(.callout).textSelection(.enabled)
                                    }
                                }
                                if group.kind == .title { Text("The titles match, but the audio may be different.").font(.caption).foregroundStyle(.secondary) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
                        }
                    }
                }.frame(maxHeight: 380)
            }
            Text("This checks audio references and titles. It does not compare the sound of different files. Nothing is removed or changed.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Check again") { check() }.disabled(loading); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 560)
        .task { check() }
    }
    private func check() {
        loading = true; failure = nil
        Task { @MainActor in
            defer { loading = false }
            do {
                if studio.demo { snapshot = source }
                else if let id = source["cardId"] as? String { snapshot = try await studio.api.card(id) }
                else { throw StudioError("Choose a saved playlist first.") }
            } catch { failure = error.localizedDescription }
        }
    }
}
