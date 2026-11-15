import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum AudioInputSource: String, CaseIterable {
    case youtube = "YouTube / SoundCloud", publicAudio = "Public audio files", localMP3 = "Local MP3s"
}

struct AudioQueueItem: Identifiable {
    let id = UUID()
    let link: URL
    var title = ""
    var audio: PreparedAudio?
    var transcode: JSON?
    var publicSource: PublicAudioTrack?
    var uploadedIcon: String?
    var message = "Waiting to download"
    var error: String?
}

struct AudioImportSheet: View {
    let card: JSON
    let service: YotoService
    let isDemo: Bool
    var initialTracks: [PublicAudioTrack] = []
    var createsPlaylist = false
    let onSaved: (JSON) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var links = ""
    @State private var source = AudioInputSource.youtube
    @State private var queue: [AudioQueueItem] = []
    @State private var missing = AudioImport.missingTools
    @State private var message = "Paste one YouTube or SoundCloud track link per line. Duplicate links are skipped."
    @State private var failure: String?
    @State private var working = false
    @State private var uploading = false
    @State private var committed = false
    @State private var creationUncertain = false
    @State private var player: AVAudioPlayer?
    @State private var task: Task<Void, Never>?
    @State private var downloaders: [Int: AudioDownloader] = [:]
    @State private var parallelLimit = 3
    @State private var showingTrimPrompt = false
    private var relevantMissingTools: [String] {
        if source == .localMP3 { return missing.filter { $0 == "ffprobe" } }
        if source == .youtube && initialTracks.isEmpty,
           let urls = try? AudioImport.mediaURLs(links), urls.allSatisfy({ $0.host == "soundcloud.com" }) {
            return missing.filter { $0 != "deno" }
        }
        return (source == .publicAudio || !initialTracks.isEmpty) ? missing.filter { ["ffmpeg", "ffprobe"].contains($0) } : missing
    }
    private var ready: [AudioQueueItem] { queue.filter { $0.audio != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add audio").font(.title2.bold())
            if createsPlaylist { Text("New playlist — saved to Yoto after the first audio upload").font(.caption).foregroundStyle(.secondary) }
            Text("Destination: \(card["title"] as? String ?? "Playlist")\(isDemo ? " (demo — upload disabled)" : "")").font(.callout).foregroundStyle(.secondary)
            if initialTracks.isEmpty {
                Picker("Audio source", selection: $source) { ForEach(AudioInputSource.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(working)
                if source == .localMP3 {
                    HStack {
                        Button("Choose MP3 files…") { chooseLocalFiles() }.disabled(working || committed)
                        Text("Select one or more files. Originals stay unchanged.").font(.caption).foregroundStyle(.secondary)
                    }
                } else { Text(source == .publicAudio ? "Direct audio-file links — one per line" : "YouTube or SoundCloud track links — one per line").font(.caption.bold()) }
            } else { Text("\(initialTracks.count) selected public audio tracks").font(.headline) }
            if initialTracks.isEmpty && source != .localMP3 { TextEditor(text: $links).font(.system(.callout, design: .monospaced)).frame(height: 85).padding(6).background(Color(nsColor: .textBackgroundColor)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3))).disabled(working) }
            Text(source == .localMP3 ? "Local MP3s keep their original quality. A separate copy is saved before upload. Yoto processes the audio for playback." : "Best available source → 320 kbps MP3. This cannot improve source quality. Yoto processes uploaded audio and may use a different final bitrate.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Simultaneous tracks").font(.caption)
                Picker("Simultaneous tracks", selection: $parallelLimit) { Text("1").tag(1); Text("2").tag(2); Text("3").tag(3) }.labelsHidden().pickerStyle(.segmented).frame(width: 150).disabled(working)
                Text("Downloads and uploads").font(.caption).foregroundStyle(.secondary)
            }
            if !relevantMissingTools.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Tools needed: " + relevantMissingTools.joined(separator: ", ")).font(.caption.bold())
                        Text(source == .youtube && initialTracks.isEmpty ? "brew install yt-dlp ffmpeg deno" : "brew install ffmpeg").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    Spacer()
                    Link("Setup guide ↗", destination: URL(string: "https://github.com/yt-dlp/yt-dlp#installation")!)
                    Button("Check tools") { missing = AudioImport.missingTools }
                }.padding(10).background(Color.orange.opacity(0.1)).cornerRadius(8)
            }
            if !queue.isEmpty {
                HStack { Text("\(ready.count) of \(queue.count) tracks ready").font(.headline); Spacer(); Text("Playlist order follows this list").font(.caption).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($queue) { $item in
                            VStack(alignment: .leading, spacing: 6) {
                                if let audio = item.audio {
                                    if let pixels = audio.artwork { HStack { Image(nsImage: PixelArt.image(pixels)).resizable().interpolation(.none).frame(width: 28, height: 28); Text("Original artwork included").font(.caption) } }
                                    TextField("Track title", text: $item.title).textFieldStyle(.roundedBorder).disabled(working)
                                    HStack {
                                        Text(String(format: "MP3 · %@ · %.0f:%02.0f · %.1f MB", audio.bitrate > 0 ? "\(audio.bitrate / 1000) kbps" : "original quality", floor(audio.duration / 60), audio.duration.truncatingRemainder(dividingBy: 60), Double(audio.bytes) / 1_000_000)).font(.caption)
                                        Spacer()
                                        Button("Preview") { play(audio) }
                                        Button("Save MP3…") { export(audio, title: item.title) }
                                    }.disabled(uploading)
                                } else { Text(item.publicSource?.title ?? (item.link.isFileURL ? item.link.lastPathComponent : item.link.absoluteString)).font(.caption).lineLimit(2) }
                                Text(item.error ?? item.message).font(.caption2).foregroundStyle(item.error == nil ? Color.secondary : Color.red).textSelection(.enabled)
                            }.padding(10).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
                        }
                    }
                }.frame(maxHeight: 260)
            }
            if working { HStack { ProgressView().controlSize(.small); Text(message).font(.callout) } }
            else { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(6) }
            Text("MP3 copies stay in Music/Yoto Playlist Studio after closing or uploading. Upload appends ready tracks at the end. Existing audio and artwork are kept. Failed imports are skipped; retry them before uploading.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(working ? "Cancel preparation" : "Close") { task?.cancel(); cancelDownloads(); dismiss() }.disabled(uploading)
                Button("Open local copies") {
                    do { try FileManager.default.createDirectory(at: AudioImport.archiveDirectory, withIntermediateDirectories: true); NSWorkspace.shared.open(AudioImport.archiveDirectory) }
                    catch { failure = "Could not open the local audio folder: " + error.localizedDescription }
                }
                if !queue.isEmpty { Button("Stop preview") { player?.stop() } }
                Spacer()
                Button(source == .localMP3 ? "Prepare / retry MP3s" : (queue.contains(where: { $0.audio != nil || $0.error != nil }) ? "Download / retry" : "Download MP3s")) { downloadAll() }.disabled(working || relevantMissingTools.count > 0 || (initialTracks.isEmpty && (source == .localMP3 ? queue.isEmpty : links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) || committed)
                Button("Upload \(ready.count) track(s)") { upload() }.buttonStyle(.borderedProminent).disabled(working || ready.isEmpty || ready.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) || isDemo || committed || creationUncertain)
            }
        }.padding(26).frame(width: 700)
        .alert("Audio exceeds Yoto’s two-hour limit", isPresented: $showingTrimPrompt) {
            Button("Trim and upload") { upload(trimLongAudio: true) }
            Button("Abort", role: .cancel) { message = "Upload aborted. Your full MP3 copies are kept." }
        } message: {
            let titles = queue.filter { ($0.audio?.duration ?? 0) > 7200 }.map(\.title).joined(separator: "\n")
            Text("\(titles)\n\nKeep only the first 1 hour, 59 minutes, 59 seconds of each oversized track? The ending will be removed from the upload copy. Full originals stay saved locally. Abort leaves the playlist unchanged.")
        }
        .interactiveDismissDisabled(uploading)
        .onAppear {
            if !initialTracks.isEmpty { queue = initialTracks.map { AudioQueueItem(link: $0.url, publicSource: $0) }; message = "Review the selected tracks, then download MP3s." }
        }
        .onChange(of: source) { _ in if !working { cleanup(); queue = []; failure = nil; message = source == .localMP3 ? "Choose MP3 files, then prepare them for upload." : source == .publicAudio ? "Paste direct audio-file links, one per line." : "Paste YouTube or SoundCloud links, one per line." } }
        .onDisappear { task?.cancel(); cancelDownloads(); player?.stop(); cleanup() }
        .onChange(of: links) { _ in
            if !working { player?.stop(); cleanup(); queue = []; failure = nil }
        }
    }
    private func cancelDownloads() {
        for downloader in downloaders.values { downloader.cancel() }
    }
    private func cleanup() {
        for item in queue { if let audio = item.audio { try? FileManager.default.removeItem(at: audio.directory) } }
    }
    private func play(_ audio: PreparedAudio) {
        do { player?.stop(); player = try AVAudioPlayer(contentsOf: audio.url); player?.play() }
        catch { failure = "Could not play the preview: " + error.localizedDescription }
    }
    private func export(_ audio: PreparedAudio, title: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mp3]
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".mp3"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(contentsOf: audio.url, options: .mappedIfSafe).write(to: url, options: .atomic) }
        catch { failure = "Could not save the MP3: " + error.localizedDescription }
    }
    private func chooseLocalFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Select MP3 files to add to this playlist. Original files will be kept."
        guard panel.runModal() == .OK else { return }
        player?.stop()
        var seen = Set(queue.map { $0.link.standardizedFileURL.resolvingSymlinksInPath() })
        for file in panel.urls where seen.insert(file.standardizedFileURL.resolvingSymlinksInPath()).inserted {
            queue.append(AudioQueueItem(link: file))
        }
        failure = nil; message = "\(queue.count) local MP3(s) selected. Prepare them, then review before uploading."
    }
    private func downloadAll() {
        do {
            if !initialTracks.isEmpty {
                if queue.isEmpty { queue = initialTracks.map { AudioQueueItem(link: $0.url, publicSource: $0) } }
            } else if source == .localMP3 {
                guard !queue.isEmpty else { throw StudioError("Choose MP3 files first.") }
            } else if source == .publicAudio {
                let tracks = try PublicAudio.directTracks(links)
                if queue.map(\.link) != tracks.map(\.url) { cleanup(); queue = tracks.map { AudioQueueItem(link: $0.url, publicSource: $0) } }
            } else {
                let urls = try AudioImport.mediaURLs(links)
                if queue.map(\.link) != urls { cleanup(); queue = urls.map { AudioQueueItem(link: $0) } }
            }
        } catch { failure = error.localizedDescription; return }
        failure = nil; working = true; player?.stop()
        task = Task { @MainActor in
            defer { working = false }
            let indices = queue.indices.filter { queue[$0].audio == nil }
            var completed = 0
            message = "Preparing \(indices.count) track(s), up to \(parallelLimit) at once…"
            await ParallelAudio.run(indices: indices, limit: parallelLimit) { index in
                let downloader = AudioDownloader()
                downloaders[index] = downloader
                defer { downloaders.removeValue(forKey: index); completed += 1 }
                queue[index].error = nil
                do {
                    let progress: (String) -> Void = { stage in queue[index].message = stage }
                    let result: PreparedAudio
                    if queue[index].link.isFileURL { result = try await downloader.prepareLocal(queue[index].link, progress: progress) }
                    else if let source = queue[index].publicSource { result = try await downloader.preparePublic(source, progress: progress) }
                    else { result = try await downloader.prepare(queue[index].link.absoluteString, progress: progress) }
                    guard !Task.isCancelled else { try? FileManager.default.removeItem(at: result.directory); return }
                    queue[index].audio = result; queue[index].title = result.title
                    queue[index].message = "Saved locally · ready to upload" + (result.artworkWarning.map { " · " + $0 } ?? "")
                } catch {
                    if Task.isCancelled { return }
                    queue[index].error = error.localizedDescription
                }
                message = "\(completed + 1)/\(indices.count) tracks prepared · up to \(parallelLimit) at once"
            }
            message = "\(ready.count)/\(queue.count) ready. Review titles and previews, then upload the ready tracks together."
        }
    }
    private func upload(trimLongAudio: Bool = false) {
        guard !ready.isEmpty else { return }
        if !trimLongAudio && ready.contains(where: { ($0.audio?.duration ?? 0) > 7200 }) {
            showingTrimPrompt = true
            return
        }
        working = true; uploading = true; failure = nil; player?.stop()
        task = Task { @MainActor in
            defer { working = false; uploading = false }
            do {
                if trimLongAudio {
                    for index in queue.indices where (queue[index].audio?.duration ?? 0) > 7200 {
                        guard let audio = queue[index].audio else { continue }
                        let downloader = AudioDownloader()
                        downloaders[index] = downloader
                        defer { downloaders.removeValue(forKey: index) }
                        queue[index].message = "Trimming a copy to fit Yoto…"
                        let trimmed = try await downloader.trim(audio)
                        queue[index].audio = trimmed
                        queue[index].transcode = nil
                        queue[index].error = nil
                        queue[index].message = "Trimmed copy ready · full original kept"
                    }
                }
                guard let id = card["cardId"] as? String else { throw StudioError("Choose an existing playlist first.") }
                // A new batch appends to the latest server playlist, not the snapshot
                // captured when this sheet opened. Check access before transferring files.
                if !createsPlaylist { _ = try await service.card(id) }
                let indices = queue.indices.filter { queue[$0].audio != nil }
                message = "Uploading and processing \(indices.count) track(s), up to \(parallelLimit) at once…"
                await ParallelAudio.run(indices: indices, limit: parallelLimit) { index in
                    queue[index].error = nil
                    do {
                        if queue[index].uploadedIcon == nil, let pixels = queue[index].audio?.artwork {
                            queue[index].message = "Uploading original artwork…"
                            queue[index].uploadedIcon = try await service.upload(pixels)
                        }
                        if queue[index].transcode == nil, let audio = queue[index].audio {
                            queue[index].transcode = try await service.uploadAudio(audio.url) { stage in queue[index].message = stage }
                        }
                        queue[index].message = "Processed by Yoto — waiting for batch save"
                    } catch { queue[index].error = error.localizedDescription }
                }
                try Task.checkCancellation()
                let failed = indices.filter { queue[$0].error != nil || queue[$0].transcode == nil }
                guard failed.isEmpty else {
                    let details = failed.prefix(3).map { index in
                        "\(queue[index].title): \(queue[index].error ?? "Audio processing is incomplete.")"
                    }.joined(separator: "\n")
                    throw StudioError("\(failed.count) track upload(s) failed. No tracks were appended.\n\(details)\nRetry Upload to reuse tracks already processed by Yoto.")
                }
                let tracks = try indices.map { index -> (transcode: JSON, title: String) in
                    guard let transcode = queue[index].transcode else { throw StudioError("Audio processing is incomplete.") }
                    return (transcode, queue[index].title)
                }
                let artwork = Dictionary(uniqueKeysWithValues: indices.enumerated().compactMap { position, index in
                    queue[index].uploadedIcon.map { (position, $0) }
                })
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("YotoPixelStudio/Backups", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let backup: (JSON) throws -> Void = { latest in
                    try JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("audio-import-" + UUID().uuidString + ".json"), options: .atomic)
                }
                message = "Adding \(tracks.count) tracks to your playlist…"
                let saved: JSON
                if createsPlaylist {
                    var payload = try AudioImport.appendBatch(tracks, to: card)
                    let references = Dictionary(uniqueKeysWithValues: artwork.map { ("\($0.key):0", $0.value) })
                    if !references.isEmpty { payload = try CardEditor.applying(references, to: payload) }
                    try backup(card)
                    payload.removeValue(forKey: "cardId")
                    message = "Creating your new playlist…"
                    creationUncertain = true
                    saved = try await service.createPlaylist(payload)
                    creationUncertain = false
                } else { saved = try await service.appendAudioBatch(tracks, artwork: artwork, to: id, backup: backup) }
                committed = true
                cleanup()
                let savedID = saved["cardId"] as? String ?? id
                let refreshed = (try? await service.card(savedID)) ?? saved
                onSaved(refreshed); dismiss()
            } catch { failure = error.localizedDescription + (creationUncertain ? " Close this window and refresh your playlists before starting again, to avoid creating a duplicate." : "") }
        }
    }
}
