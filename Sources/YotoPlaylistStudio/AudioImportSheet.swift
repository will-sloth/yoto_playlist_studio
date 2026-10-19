import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct AudioQueueItem: Identifiable {
    let id = UUID()
    let link: URL
    var title = ""
    var audio: PreparedAudio?
    var transcode: JSON?
    var message = "Waiting to download"
    var error: String?
}

struct AudioImportSheet: View {
    let card: JSON
    let service: YotoService
    let isDemo: Bool
    let onSaved: (JSON) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var links = ""
    @State private var queue: [AudioQueueItem] = []
    @State private var missing = AudioImport.missingTools
    @State private var message = "Paste one YouTube video link per line. Duplicate links are skipped."
    @State private var failure: String?
    @State private var working = false
    @State private var uploading = false
    @State private var committed = false
    @State private var player: AVAudioPlayer?
    @State private var task: Task<Void, Never>?
    @State private var downloader = AudioDownloader()
    private var ready: [AudioQueueItem] { queue.filter { $0.audio != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add audio from YouTube").font(.title2.bold())
            Text("Destination: \(card["title"] as? String ?? "Playlist")\(isDemo ? " (demo — upload disabled)" : "")").font(.callout).foregroundStyle(.secondary)
            Text("YouTube video links — one per line").font(.caption.bold())
            TextEditor(text: $links).font(.system(.callout, design: .monospaced)).frame(height: 85).padding(6).background(Color(nsColor: .textBackgroundColor)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3))).disabled(working)
            Text("Best available source → 320 kbps MP3. This cannot improve source quality. Yoto processes uploaded audio and may use a different final bitrate.").font(.caption).foregroundStyle(.secondary)
            if !missing.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Tools needed: " + missing.joined(separator: ", ")).font(.caption.bold())
                        Text("brew install yt-dlp ffmpeg deno").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
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
                                    TextField("Track title", text: $item.title).textFieldStyle(.roundedBorder).disabled(working)
                                    HStack {
                                        Text(String(format: "MP3 · 320 kbps · %.0f:%02.0f · %.1f MB", floor(audio.duration / 60), audio.duration.truncatingRemainder(dividingBy: 60), Double(audio.bytes) / 1_000_000)).font(.caption)
                                        Spacer()
                                        Button("Preview") { play(audio) }
                                        Button("Save MP3…") { export(audio, title: item.title) }
                                    }.disabled(uploading)
                                } else { Text(item.link.absoluteString).font(.caption).lineLimit(1) }
                                Text(item.error ?? item.message).font(.caption2).foregroundStyle(item.error == nil ? Color.secondary : Color.red).textSelection(.enabled)
                            }.padding(10).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
                        }
                    }
                }.frame(maxHeight: 260)
            }
            if working { HStack { ProgressView().controlSize(.small); Text(message).font(.callout) } }
            else { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(6) }
            Text("MP3 copies stay in Music/Yoto Playlist Studio after closing or uploading. Upload appends the ready tracks together at the end. Existing audio and artwork are kept. Failed downloads are skipped; you can retry them before uploading.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(working ? "Cancel downloads" : "Close") { task?.cancel(); downloader.cancel(); dismiss() }.disabled(uploading)
                Button("Open local copies") {
                    do { try FileManager.default.createDirectory(at: AudioImport.archiveDirectory, withIntermediateDirectories: true); NSWorkspace.shared.open(AudioImport.archiveDirectory) }
                    catch { failure = "Could not open the local audio folder: " + error.localizedDescription }
                }
                if !queue.isEmpty { Button("Stop preview") { player?.stop() } }
                Spacer()
                Button(queue.isEmpty ? "Download MP3s" : "Download / retry") { downloadAll() }.disabled(working || !missing.isEmpty || links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || committed)
                Button("Upload \(ready.count) track(s)") { upload() }.buttonStyle(.borderedProminent).disabled(working || ready.isEmpty || ready.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) || isDemo || committed)
            }
        }.padding(26).frame(width: 700)
        .interactiveDismissDisabled(uploading)
        .onDisappear { task?.cancel(); downloader.cancel(); player?.stop(); cleanup() }
        .onChange(of: links) { _ in
            if !working { player?.stop(); cleanup(); queue = []; failure = nil }
        }
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
    private func downloadAll() {
        let urls: [URL]
        do { urls = try AudioImport.youtubeURLs(links) }
        catch { failure = error.localizedDescription; return }
        if queue.map(\.link) != urls { cleanup(); queue = urls.map { AudioQueueItem(link: $0) } }
        failure = nil; working = true; player?.stop()
        task = Task { @MainActor in
            defer { working = false }
            for index in queue.indices where queue[index].audio == nil {
                guard !Task.isCancelled else { return }
                queue[index].error = nil
                do {
                    let result = try await downloader.prepare(queue[index].link.absoluteString) { stage in
                        message = "Track \(index + 1)/\(queue.count): \(stage)"; queue[index].message = stage
                    }
                    guard !Task.isCancelled else { try? FileManager.default.removeItem(at: result.directory); return }
                    queue[index].audio = result; queue[index].title = result.title; queue[index].message = "Saved locally in Music/Yoto Playlist Studio · ready to upload"
                } catch {
                    if Task.isCancelled { return }
                    queue[index].error = error.localizedDescription
                }
            }
            message = "\(ready.count)/\(queue.count) downloaded. Review titles and previews, then upload the ready tracks together."
        }
    }
    private func upload() {
        guard !ready.isEmpty else { return }
        working = true; uploading = true; failure = nil; player?.stop()
        task = Task { @MainActor in
            defer { working = false; uploading = false }
            do {
                guard let id = card["cardId"] as? String else { throw StudioError("Choose an existing playlist first.") }
                let fresh = try await service.card(id)
                guard try sameCard(fresh, card) else { throw StudioError("This playlist changed. Close and reopen it before uploading.") }
                let indices = queue.indices.filter { queue[$0].audio != nil }
                for (position, index) in indices.enumerated() {
                    if queue[index].transcode == nil, let audio = queue[index].audio {
                        queue[index].transcode = try await service.uploadAudio(audio.url) { stage in message = "Track \(position + 1)/\(indices.count): \(stage)" }
                        queue[index].message = "Audio processed by Yoto — waiting for batch save"
                    }
                }
                let latest = try await service.card(id)
                guard try sameCard(latest, fresh) else { throw StudioError("The playlist changed during upload. No batch tracks were appended. Close and reload before retrying.") }
                let tracks = try indices.map { index -> (transcode: JSON, title: String) in
                    guard let transcode = queue[index].transcode else { throw StudioError("Audio processing is incomplete.") }
                    return (transcode, queue[index].title)
                }
                let payload = try AudioImport.appendBatch(tracks, to: latest)
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("YotoPixelStudio/Backups", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("audio-import-" + UUID().uuidString + ".json"), options: .atomic)
                message = "Adding \(tracks.count) tracks to your playlist…"
                let saved = try await service.save(payload)
                committed = true
                cleanup()
                let refreshed = (try? await service.card(id)) ?? saved
                onSaved(refreshed); dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
    private func sameCard(_ lhs: JSON, _ rhs: JSON) throws -> Bool {
        try JSONSerialization.data(withJSONObject: lhs["content"] ?? [:], options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: rhs["content"] ?? [:], options: [.sortedKeys]) && (lhs["updatedAt"] as? String) == (rhs["updatedAt"] as? String)
    }
}
