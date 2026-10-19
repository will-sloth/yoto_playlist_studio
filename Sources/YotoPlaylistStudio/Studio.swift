import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class Studio: ObservableObject {
    @Published var clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
    @Published var playlists: [Playlist] = []
    @Published var newPlaylists: [String: JSON] = [:]
    @Published var icons: [LibraryIcon] = []
    @Published var existingIconURLs: [String: URL] = [:]
    @Published var iconLoadMessage: String?
    func existingIconURL(_ row: TrackRow) -> URL? {
        if let url = row.iconURL { return url }
        guard let reference = row.icon else { return nil }
        if let url = existingIconURLs[reference] { return url }
        return icons.first { "yoto:#" + $0.id == reference || "yoto:" + $0.id == reference }?.url
    }
    func loadExistingIcons() async {
        existingIconURLs = [:]; iconLoadMessage = nil
        guard !demo, connected, let id = card["cardId"] as? String, newPlaylists[id] == nil else { return }
        do {
            let owned = try await api.icons(owned: true)
            guard selectedPlaylist == id, connected else { return }
            existingIconURLs = IconPreview.urls(owned)
        } catch {
            guard selectedPlaylist == id, connected else { return }
            iconLoadMessage = "Custom icon library could not load: " + error.localizedDescription
        }
        let references = Set(rows.filter { existingIconURL($0) == nil }.compactMap(\.icon))
        for reference in references where reference.hasPrefix("yoto:") {
            let url = try? await api.iconURL(cardID: id, reference: reference)
            guard selectedPlaylist == id, connected else { return }
            if let url { existingIconURLs[reference] = url }
        }
        let unresolved = rows.filter { $0.icon != nil && existingIconURL($0) == nil }.count
        if unresolved > 0 && iconLoadMessage == nil {
            iconLoadMessage = "\(unresolved) existing icon preview(s) could not be loaded. Your artwork is kept."
        }
    }
    @Published var selectedPlaylist: String?
    @Published var selectedTracks = Set<String>()
    @Published var card: JSON = [:]
    @Published var draft: [String: ArtChoice] = [:]
    @Published var suggestions: [String: IconSuggestion] = [:]
    @Published var rejected: [String: Set<String>] = [:]
    func suggestIcons(onlyMissing: Bool = false) {
        for row in rows where IconSuggestions.shouldSuggest(row, automatically: onlyMissing, hasStagedArt: draft[row.id] != nil) && !(onlyMissing && demoArt[row.id] != nil) {
            var excluded = rejected[row.id] ?? []
            if let icon = row.icon, icon.hasPrefix("yoto:#") { excluded.insert(String(icon.dropFirst(6))) }
            suggestions[row.id] = IconSuggestions.suggest(title: row.title, icons: demo ? [] : icons, excluding: excluded)
        }
        status = suggestions.isEmpty ? "Existing artwork is kept. Request alternatives whenever you want." : "Suggestions ready. Accept stages an icon; Reject keeps your current art."
    }
    func retrySuggestion(_ row: TrackRow, query: String) {
        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var excluded = rejected[row.id] ?? []
        if let icon = row.icon, icon.hasPrefix("yoto:#") { excluded.insert(String(icon.dropFirst(6))) }
        suggestions[row.id] = IconSuggestions.suggest(title: title.isEmpty ? row.title : title, icons: demo ? [] : icons, excluding: excluded)
        status = suggestions[row.id] == nil ? "No other matching icons. Refine the search or create new pixel art." : "Another icon is ready to accept or reject."
    }
    func useCommunity(_ selection: CommunitySelection, pixels: [UInt32], source: String) {
        let valid = Set(rows.map(\.id))
        guard selection.trackIDs.isSubset(of: valid) else { error = "The playlist changed. Reopen community icons for the current tracks."; return }
        for id in selection.trackIDs { draft[id] = .pixels(pixels); suggestions.removeValue(forKey: id) }
        self.pixels = pixels; selectedTracks = selection.trackIDs
        status = "Community icon from \(source) staged for \(selection.trackIDs.count) track(s). Review before saving."
    }
    func useGenerated(_ row: TrackRow, pixels: [UInt32]) {
        suggestions.removeValue(forKey: row.id)
        draft[row.id] = .pixels(pixels)
        self.pixels = pixels; selectedTracks = [row.id]
        status = "New pixel art accepted and staged. Review changes before saving."
    }
    func acceptSuggestion(_ id: String) {
        guard let suggestion = suggestions.removeValue(forKey: id) else { return }
        draft[id] = suggestion.art
        status = "Artwork accepted and staged. Review changes before saving."
    }
    func rejectSuggestion(_ id: String) {
        guard let suggestion = suggestions.removeValue(forKey: id) else { return }
        rejected[id, default: []].insert(IconSuggestions.identity(suggestion))
        status = "Suggestion rejected. Current track artwork is unchanged."
    }
    @Published var pixels = PixelArt.template("Star", color: 0xFFC857FF)
    @Published var status = "Connect Yoto or explore the demo."
    @Published var error: String?
    @Published var busy = false
    @Published var connected = false
    @Published var demo = false
    @Published var review = false
    @Published var demoArt: [String: ArtChoice] = [:]
    let api = YotoService()
    var rows: [TrackRow] { CardEditor.rows(card) }
    var hasChanges: Bool { !draft.isEmpty }
    func run(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }
    func startPlaylist(title: String) throws {
        var draftCard = try CardEditor.newPlaylist(title: title)
        let id = "new-" + UUID().uuidString
        draftCard["cardId"] = id
        newPlaylists[id] = draftCard
        playlists.append(Playlist(id: id, title: (draftCard["title"] as? String ?? "New playlist") + " (new)"))
        card = draftCard; selectedPlaylist = id; selectedTracks = []; draft = [:]; suggestions = [:]; rejected = [:]
        existingIconURLs = [:]; iconLoadMessage = nil
        status = "New playlist ready. Add audio to save it to Yoto."
    }
    func refreshPlaylists() {
        run {
            let saved = try await self.api.playlists()
            let pending = self.newPlaylists.compactMap { id, card in (card["title"] as? String).map { Playlist(id: id, title: $0 + " (new)") } }
            self.playlists = saved + pending
            self.status = "Playlist list refreshed."
        }
    }
    func connect() {
        run {
            try await self.api.login(clientID: self.clientID)
            UserDefaults.standard.set(self.clientID, forKey: "clientID")
            self.connected = true; self.demo = false
            self.suggestions = [:]; self.rejected = [:]; self.newPlaylists = [:]
            self.card = [:]; self.draft = [:]; self.selectedTracks = []; self.selectedPlaylist = nil
            self.playlists = try await self.api.playlists()
            self.status = "Connected · \(self.playlists.count) playlists"
            self.icons = try await self.api.icons()
        }
    }
    func disconnect() {
        suggestions = [:]; rejected = [:]
        api.disconnect(); newPlaylists = [:]; connected = false; demo = false; playlists = []; icons = []
        selectedPlaylist = nil; card = [:]; draft = [:]; selectedTracks = []
        status = "Disconnected."
    }
    func load(_ id: String) {
        guard id != selectedPlaylist else { return }
        if hasChanges {
            let alert = NSAlert(); alert.messageText = "Discard staged artwork?"
            alert.informativeText = "Your changes have not been sent to Yoto."
            alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Keep editing")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        run {
            let result: JSON
            if let pending = self.newPlaylists[id] { result = pending }
            else { result = self.demo ? Self.demoCard : try await self.api.card(id) }
            self.suggestions = [:]; self.rejected = [:]
            self.card = result; self.selectedPlaylist = id; self.draft = [:]; self.selectedTracks = []
            self.suggestIcons(onlyMissing: true)
            await self.loadExistingIcons()
        }
    }
    func openDemo() {
        suggestions = [:]; rejected = [:]
        newPlaylists = [:]; demo = true; connected = false; demoArt = [:]
        playlists = [Playlist(id: "demo", title: "Bedtime adventures")]
        card = Self.demoCard; selectedPlaylist = "demo"; selectedTracks = []; draft = [:]
        suggestIcons(onlyMissing: true)
    }
    static var demoCard: JSON {
        ["cardId": "demo", "title": "Bedtime adventures", "content": ["chapters": ["Twinkle, twinkle", "A trip to the moon", "The sleepy forest", "A little love song", "Polar Bear, Polar Bear, What Do You Hear?"].enumerated().map { i, title -> JSON in
            ["key": "\(i)", "title": title, "tracks": [["key": "\(i)", "title": title, "trackUrl": "demo://audio/\(i)"]]]
        }]]
    }
    func stage(_ choice: ArtChoice) {
        for id in selectedTracks { draft[id] = choice; suggestions.removeValue(forKey: id) }
        status = "\(draft.count) track icon(s) staged. Review before applying."
    }
    func importArt() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { pixels = try PixelArt.importImage(url); status = "Imported and fitted to 16×16. Check the preview before using." }
        catch { self.error = error.localizedDescription }
    }
    func exportArt() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "yoto-icon.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try PixelArt.png(pixels).write(to: url); status = "Saved 16×16 PNG." } catch { self.error = error.localizedDescription }
    }
    func apply() {
        review = false
        run {
            guard let id = self.selectedPlaylist, self.hasChanges else { return }
            if self.demo { self.demoArt.merge(self.draft) { _, new in new }; self.draft = [:]; self.status = "Demo artwork applied locally. No Yoto account changed."; return }
            // Refuse stale edits instead of silently overwriting changes from another app.
            let fresh = try await self.api.card(id)
            let oldData = try JSONSerialization.data(withJSONObject: self.card["content"] ?? [:], options: [.sortedKeys])
            let newData = try JSONSerialization.data(withJSONObject: fresh["content"] ?? [:], options: [.sortedKeys])
            guard oldData == newData,
                  (self.card["updatedAt"] as? String) == (fresh["updatedAt"] as? String) else {
                throw StudioError("This playlist changed in Yoto while you were editing. Your art is still staged. Export any custom art, discard the staged changes, then reopen this playlist before trying again.")
            }
            let backupDir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("YotoPixelStudio/Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let backup = backupDir.appendingPathComponent("playlist-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: fresh, options: [.prettyPrinted, .sortedKeys]).write(to: backup, options: .atomic)
            var references: [String: String] = [:]
            var uploaded: [Data: String] = [:]
            for (track, art) in self.draft {
                switch art {
                case .library(let icon): references[track] = "yoto:#" + icon.id
                case .pixels(let pixels):
                    let data = try PixelArt.png(pixels)
                    if let cached = uploaded[data] { references[track] = cached }
                    else { let ref = try await self.api.upload(pixels); uploaded[data] = ref; references[track] = ref }
                }
            }
            let payload = try CardEditor.applying(references, to: fresh)
            try await self.api.save(payload)
            // Clear staged edits as soon as the write succeeds, even if the reload fails.
            self.draft = [:]
            self.card = try await self.api.card(id)
            await self.loadExistingIcons()
            self.status = "Artwork saved to Yoto · backup saved on this Mac."
        }
    }
}

@main
struct YotoPlaylistStudioApp: App {
    @StateObject private var studio = Studio()
    var body: some Scene {
        WindowGroup { StudioView().environmentObject(studio).frame(minWidth: 1080, minHeight: 720).onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) } }
            .windowStyle(.hiddenTitleBar)
    }
}

private struct AudioImportSelection: Identifiable {
    let id = UUID()
    let tracks: [PublicAudioTrack]
}

struct StudioView: View {
    @EnvironmentObject var studio: Studio
    @State private var settings = false
    @State private var audioSelection: AudioImportSelection?
    @State private var publicAudio = false
    @State private var newPlaylistSheet = false
    @State private var playlistName = ""
    @State private var playlistNameError: String?
    @State private var importTracks: [PublicAudioTrack] = []
    @State private var search = ""
    @State private var retryQueries: [String: String] = [:]
    @State private var generationTrack: TrackRow?
    @State private var communitySelection: CommunitySelection?
    @State private var tab = 0
    @State private var brush: UInt32 = 0xFFC857FF
    @State private var template = "Star"
    @State private var undo: [[UInt32]] = []
    private let accent = Color(red: 0.12, green: 0.48, blue: 0.4)
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 235)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(studio.card["title"] as? String ?? "A little art. A lot of personality.").font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text(studio.demo ? "DEMO PLAYLIST · LOCAL PREVIEW" : "AUDIO AND ARTWORK FOR YOUR YOTO PLAYLISTS").font(.system(size: 10, weight: .bold)).tracking(1.8).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if studio.busy { ProgressView().controlSize(.small) }
                    Button("Add audio…") { importTracks = []; audioSelection = AudioImportSelection(tracks: []) }.disabled(studio.selectedPlaylist == nil || studio.hasChanges || studio.busy).help(studio.hasChanges ? "Apply or discard staged artwork before adding audio" : "Import YouTube links or public audio files")
                    Button("Public-domain audio…") { importTracks = []; publicAudio = true }.disabled(studio.selectedPlaylist == nil || studio.hasChanges || studio.busy)
                    Button("Review \(studio.draft.count) changes") { studio.review = true }.buttonStyle(.borderedProminent).tint(accent).disabled(!studio.hasChanges || studio.busy)
                }
                HStack(alignment: .top, spacing: 24) {
                    tracks.frame(minWidth: 260, idealWidth: 310, maxWidth: 400)
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Artwork source", selection: $tab) { Text("Create art").tag(0); Text("Yoto library").tag(1); Text("Community").tag(2) }.pickerStyle(.segmented)
                        if tab == 0 { editor } else if tab == 1 { library } else { community }
                    }.frame(minWidth: 360, maxWidth: .infinity)
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Circle().fill(studio.demo ? Color.orange : studio.connected ? accent : Color.gray).frame(width: 7, height: 7)
                    Text(studio.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }.padding(28).background(Color(nsColor: .windowBackgroundColor))
        }.tint(accent)
        .disabled(studio.busy)
        .sheet(item: $audioSelection) { selection in
            AudioImportSheet(card: studio.card, service: studio.api, isDemo: studio.demo, initialTracks: selection.tracks, createsPlaylist: studio.selectedPlaylist.map { studio.newPlaylists[$0] != nil } ?? false) { payload in
                if let previous = studio.selectedPlaylist, studio.newPlaylists.removeValue(forKey: previous) != nil {
                    studio.playlists.removeAll { $0.id == previous }
                }
                studio.card = payload
                if let id = payload["cardId"] as? String {
                    studio.selectedPlaylist = id
                    if !studio.playlists.contains(where: { $0.id == id }) { studio.playlists.append(Playlist(id: id, title: payload["title"] as? String ?? "Playlist")) }
                }
                Task { await studio.loadExistingIcons() }
                studio.suggestions = [:]; studio.rejected = [:]
                studio.suggestIcons(onlyMissing: true)
                studio.status = "Audio added to Yoto. Choose artwork for the new track."
            }
        }
        .sheet(isPresented: $publicAudio, onDismiss: { if !importTracks.isEmpty { audioSelection = AudioImportSelection(tracks: importTracks) } }) {
            PublicAudioSheet { tracks in importTracks = tracks }
        }
        .sheet(isPresented: $newPlaylistSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New playlist").font(.title2.bold())
                TextField("Playlist name", text: $playlistName).textFieldStyle(.roundedBorder)
                Text("Choose a name, then add audio. The playlist is saved to Yoto when you upload its first track.").font(.callout).foregroundStyle(.secondary)
                if let error = playlistNameError { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") { newPlaylistSheet = false }; Spacer()
                    Button("Start playlist") {
                        do { try studio.startPlaylist(title: playlistName); newPlaylistSheet = false }
                        catch { playlistNameError = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(26).frame(width: 420)
        }
        .sheet(isPresented: $settings) { connectionSheet }
        .sheet(isPresented: $studio.review) { reviewSheet }
        .sheet(item: $generationTrack) { row in
            GenerationSheet(row: row) { pixels in studio.useGenerated(row, pixels: pixels) }
        }
        .sheet(item: $communitySelection) { selection in
            CommunitySheet(selection: selection) { pixels, source in studio.useCommunity(selection, pixels: pixels, source: source) }
        }
        .onChange(of: studio.selectedPlaylist) { _ in retryQueries = [:] }
        .alert("Couldn’t complete that", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) { Button("OK") { studio.error = nil } } message: { Text(studio.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.fill").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) { Text("Playlist Studio").font(.system(size: 20, weight: .bold, design: .rounded)); Text("for Yoto").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 15)
            Button { settings = true } label: { Label(studio.connected ? "Yoto connected" : "Connect to Yoto", systemImage: "person.crop.circle") }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            Button("New playlist…", systemImage: "plus") { playlistName = ""; playlistNameError = nil; newPlaylistSheet = true }.disabled((!studio.connected && !studio.demo) || studio.hasChanges || studio.busy)
            HStack {
                Text("YOUR PLAYLISTS").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                if studio.connected { Button("Refresh") { studio.refreshPlaylists() }.font(.caption).disabled(studio.busy) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(studio.playlists) { playlist in
                        Button { studio.load(playlist.id) } label: {
                            HStack { Image(systemName: "rectangle.stack"); Text(playlist.title).lineLimit(2); Spacer() }
                                .padding(10).background(studio.selectedPlaylist == playlist.id ? accent.opacity(0.12) : .clear).cornerRadius(9)
                        }.buttonStyle(.plain)
                    }
                    if studio.playlists.isEmpty { Text("Your Make Your Own playlists will appear here.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8) }
                }
            }
            Spacer()
            if !studio.connected { Button("Explore demo playlist") { studio.openDemo() }.buttonStyle(.plain).foregroundStyle(accent) }
            Text("16 × 16 pixels.\nMade for little listeners.").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(20).background(Color(nsColor: .controlBackgroundColor))
    }
    private var tracks: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("1. Choose tracks").font(.headline); Spacer(); Button("All") { studio.selectedTracks = Set(studio.rows.map(\.id)) }.disabled(studio.rows.isEmpty) }
            Text("Select tracks to choose art manually, or suggest an icon for each song.").font(.caption).foregroundStyle(.secondary)
            Button("Suggest icons for songs", systemImage: "sparkles") { studio.suggestIcons() }.disabled(studio.rows.isEmpty)
            Text("Existing artwork is kept. Automatic suggestions appear only for tracks without art.").font(.caption2).foregroundStyle(.secondary)
            if studio.connected && !studio.rows.isEmpty {
                Button("Reload icons") { studio.run { await studio.loadExistingIcons() } }.font(.caption)
                if let message = studio.iconLoadMessage { Text(message).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            if studio.rows.isEmpty {
                VStack(spacing: 16) { Image(systemName: "music.note.list").font(.system(size: 35)).foregroundStyle(accent); Text(studio.selectedPlaylist == nil ? "Choose a playlist to get started" : "Add audio to get started").foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, minHeight: 240)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(studio.rows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 6) {
                        Button {
                            if studio.selectedTracks.contains(row.id) { studio.selectedTracks.remove(row.id) } else { studio.selectedTracks.insert(row.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: studio.selectedTracks.contains(row.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(accent)
                                trackArt(row).frame(width: 36, height: 36).background(Color.black).cornerRadius(5)
                                VStack(alignment: .leading, spacing: 4) { Text(row.title).font(.callout).lineLimit(2); Text(studio.draft[row.id] != nil ? "New artwork staged" : "Track \(index + 1)").font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                            }.padding(12).background(studio.selectedTracks.contains(row.id) ? accent.opacity(0.1) : Color(nsColor: .controlBackgroundColor)).cornerRadius(10)
                        }.buttonStyle(.plain)
                        if row.icon != nil && studio.suggestions[row.id] == nil && studio.draft[row.id] == nil && studio.rejected[row.id]?.isEmpty != false {
                            Button("Suggest a different icon") { studio.retrySuggestion(row, query: row.title) }.font(.caption).padding(.horizontal, 12)
                        }
                        if let suggestion = studio.suggestions[row.id] {
                            HStack(alignment: .top, spacing: 10) {
                                suggestionArt(suggestion).frame(width: 38, height: 38).padding(5).background(.black).cornerRadius(6)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(suggestion.title).font(.caption.bold())
                                    Text(suggestion.reason).font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Button("Accept") { studio.acceptSuggestion(row.id) }.tint(accent)
                                        Button("Reject") { studio.rejectSuggestion(row.id) }
                                    }.buttonStyle(.bordered).controlSize(.small)
                                }
                                Spacer(minLength: 0)
                            }.padding(10).background(accent.opacity(0.07)).cornerRadius(8)
                        } else if studio.rejected[row.id]?.isEmpty == false && studio.draft[row.id] == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Not quite right? Try another icon or create your own.").font(.caption)
                                TextField("Search subject, e.g. polar bear", text: Binding(get: { retryQueries[row.id] ?? row.title }, set: { retryQueries[row.id] = $0 })).textFieldStyle(.roundedBorder)
                                HStack {
                                    Button("Try another match") { studio.retrySuggestion(row, query: retryQueries[row.id] ?? row.title) }
                                    Button("Create new pixel art…") { generationTrack = row }
                                }.controlSize(.small)
                                Button("Search community icons…") {
                                    communitySelection = CommunitySelection(trackIDs: [row.id], title: row.title, query: CommunitySource.suggestedQuery(retryQueries[row.id] ?? row.title))
                                }.controlSize(.small)
                                Text("Previously rejected icons are skipped.").font(.caption2).foregroundStyle(.secondary)
                            }.padding(10).background(accent.opacity(0.07)).cornerRadius(8)
                        }
                        }
                    }
                }
            }
            if studio.hasChanges { Button("Discard staged changes") { studio.draft = [:] }.font(.caption) }
        }
    }
    @ViewBuilder private func suggestionArt(_ suggestion: IconSuggestion) -> some View {
        switch suggestion.art {
        case .pixels(let pixels): Image(nsImage: PixelArt.image(pixels)).interpolation(.none).resizable().scaledToFit()
        case .library(let icon): remoteIcon(icon.url)
        }
    }
    @ViewBuilder private func trackArt(_ row: TrackRow) -> some View {
        if let art = studio.draft[row.id] ?? (studio.demo ? studio.demoArt[row.id] : nil) {
            switch art {
            case .pixels(let pixels): Image(nsImage: PixelArt.image(pixels)).interpolation(.none).resizable().scaledToFit()
            case .library(let icon): remoteIcon(icon.url)
            }
        } else if let url = studio.existingIconURL(row) { remoteIcon(url) }
        else { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5)) }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("2. Make it theirs").font(.headline); Spacer(); Text("16 × 16 PNG").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: 18) {
                PixelCanvas(pixels: $studio.pixels, brush: brush, onStroke: { undo.append(studio.pixels); if undo.count > 50 { undo.removeFirst() } }).frame(width: 272, height: 272).cornerRadius(10)
                VStack(spacing: 10) {
                    Image(nsImage: PixelArt.image(studio.pixels)).interpolation(.none).resizable().frame(width: 64, height: 64).padding(12).background(Color.black).cornerRadius(12)
                    Text("Player preview").font(.caption2).foregroundStyle(.secondary)
                    Button("Undo") { if let last = undo.popLast() { studio.pixels = last } }.disabled(undo.isEmpty)
                }
            }
            HStack(spacing: 7) {
                ForEach(PixelArt.palette, id: \.self) { color in
                    Button { brush = color } label: {
                        ZStack {
                            Circle().fill(color == 0 ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: NSColor(srgbRed: Double((color >> 24) & 255)/255, green: Double((color >> 16) & 255)/255, blue: Double((color >> 8) & 255)/255, alpha: 1)))
                            if color == 0 { Image(systemName: "eraser").font(.system(size: 10)).foregroundStyle(.secondary) }
                        }.frame(width: 20, height: 20).overlay(Circle().stroke(brush == color ? accent : .gray.opacity(0.4), lineWidth: brush == color ? 3 : 1))
                    }.buttonStyle(.plain).help(color == 0 ? "Eraser" : "Choose color")
                }
            }
            HStack {
                Picker("Start from", selection: $template) { ForEach(PixelArt.templates, id: \.self) { Text($0) } }.frame(width: 190)
                Button("Create") { undo.append(studio.pixels); studio.pixels = PixelArt.template(template, color: brush == 0 ? 0xFFC857FF : brush) }
                Button("Clear") { undo.append(studio.pixels); studio.pixels = [UInt32](repeating: 0, count: 256) }
            }
            HStack { Button("Import image…") { undo.append(studio.pixels); studio.importArt() }; Button("Export PNG…") { studio.exportArt() } }
            Text("Draw on the grid or start from a design. Imported images are fitted to 16×16; simple shapes work best.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Use art for \(studio.selectedTracks.count) selected track(s)") { studio.stage(.pixels(studio.pixels)) }.buttonStyle(.borderedProminent).tint(accent).disabled(studio.selectedTracks.isEmpty)
        }
    }
    private var community: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("2. Explore community art").font(.headline)
            Text("Browse Yoto Icons and Yoto Everything inside Playlist Studio. No OpenAI API key needed.").font(.callout).foregroundStyle(.secondary)
            Label("Yoto Icons", systemImage: "square.grid.3x3").font(.headline)
            Text("Search community-made icons by subject, then choose Download to preview your pick.").font(.caption).foregroundStyle(.secondary)
            Label("Yoto Everything", systemImage: "sparkles").font(.headline)
            Text("Browse free 16×16 icons. Use Find on page or explore the categories.").font(.caption).foregroundStyle(.secondary)
            Button("Browse community icons…") {
                let selected = studio.rows.filter { studio.selectedTracks.contains($0.id) }
                let query = selected.count == 1 ? CommunitySource.suggestedQuery(selected[0].title) : ""
                communitySelection = CommunitySelection(trackIDs: studio.selectedTracks, title: "Artwork for \(selected.count) selected track(s)", query: query)
            }.buttonStyle(.borderedProminent).disabled(studio.selectedTracks.isEmpty)
            Text("Select tracks first. Downloaded art opens as a preview; Accept icon stages it for those tracks. Your final review controls what gets saved to Yoto.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
    private var filteredIcons: [LibraryIcon] { studio.icons.filter { search.isEmpty || ($0.title + " " + $0.tags.joined(separator: " ")).localizedCaseInsensitiveContains(search) } }
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Find their next favorite").font(.headline)
            TextField("Search Yoto icons by name or tag", text: $search).textFieldStyle(.roundedBorder)
            if !studio.connected { Text("Connect your Yoto account to browse its public icon library.").foregroundStyle(.secondary).padding(.vertical, 40) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82))], spacing: 12) {
                    ForEach(filteredIcons) { icon in
                        Button { studio.stage(.library(icon)) } label: {
                            VStack(spacing: 6) { remoteIcon(icon.url).frame(width: 48, height: 48).padding(10).background(Color.black).cornerRadius(8); Text(icon.title).font(.caption2).lineLimit(2).frame(height: 28) }
                        }.buttonStyle(.plain).disabled(studio.selectedTracks.isEmpty).help("Use \(icon.title) for selected tracks")
                    }
                }
                if studio.connected && filteredIcons.isEmpty { Text("No matching icons. Try a different search.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func remoteIcon(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().interpolation(.none).scaledToFit() }
            else { Image(systemName: "square.dotted").foregroundStyle(.white.opacity(0.5)) }
        }
    }
    private var connectionSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect your Yoto").font(.title2.bold())
            Text("Create a Public Client in the Yoto developer dashboard. Register this callback URL:")
            Text("http://127.0.0.1:8787/callback").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            Link("Open Yoto developer dashboard ↗", destination: URL(string: "https://dashboard.yoto.dev/")!)
            TextField("Yoto Client ID", text: $studio.clientID).textFieldStyle(.roundedBorder)
            Text("Sign in securely in your browser. No client secret is needed. Your session is kept in memory and ends when you quit; the Client ID is remembered.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Close") { settings = false }; Spacer(); if studio.connected { Button("Disconnect") { studio.disconnect(); settings = false } }; Button("Sign in with Yoto") { settings = false; studio.connect() }.buttonStyle(.borderedProminent).disabled(studio.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(30).frame(width: 480)
    }
    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready for a little personality?").font(.title2.bold())
            Text("\(studio.draft.count) track icon(s) in “\(studio.card["title"] as? String ?? "Playlist")” will change. Audio, track order and playlist settings are preserved.")
            ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(studio.rows.filter { studio.draft[$0.id] != nil }) { row in HStack { trackArt(row).frame(width: 32, height: 32).background(.black).cornerRadius(4); Text(row.title); Spacer() } } } }.frame(maxHeight: 240)
            Text(studio.demo ? "This is a local demo. Nothing will be sent to Yoto." : "A copy of the original playlist is saved in Application Support/YotoPixelStudio/Backups before uploading.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Keep editing") { studio.review = false }; Spacer(); Button(studio.demo ? "Apply to demo" : "Apply to Yoto") { studio.apply() }.buttonStyle(.borderedProminent) }
        }.padding(30).frame(width: 480)
    }
}

struct PixelCanvas: View {
    @Binding var pixels: [UInt32]
    var brush: UInt32
    var onStroke: () -> Void
    @State private var drawing = false
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 16
            for y in 0..<16 { for x in 0..<16 {
                let c = pixels[y * 16 + x]
                let color = c & 255 == 0 ? Color(white: (x + y) % 2 == 0 ? 0.12 : 0.16) : Color(nsColor: NSColor(srgbRed: Double((c >> 24) & 255)/255, green: Double((c >> 16) & 255)/255, blue: Double((c >> 8) & 255)/255, alpha: Double(c & 255)/255))
                context.fill(Path(CGRect(x: Double(x) * cell, y: Double(y) * cell, width: cell - 0.5, height: cell - 0.5)), with: .color(color))
            } }
        }.background(.black).contentShape(Rectangle()).overlay {
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if !drawing { onStroke(); drawing = true }
                    let x = Int(value.location.x / geometry.size.width * 16), y = Int(value.location.y / geometry.size.height * 16)
                    if (0..<16).contains(x) && (0..<16).contains(y) { pixels[y * 16 + x] = brush }
                }.onEnded { _ in drawing = false })
            }
        }.accessibilityLabel("16 by 16 pixel drawing canvas")
    }
}
