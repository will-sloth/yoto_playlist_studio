import Foundation

struct PreparedAudio {
    let url: URL
    let title: String
    let duration: Double
    let bytes: Int
    let bitrate: Int
    let directory: URL
    var artwork: [UInt32]? = nil
    var artworkWarning: String? = nil
}

enum AudioImport {
    static var archiveDirectory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("Yoto Playlist Studio", isDirectory: true)
    }
    static func keepLocalCopy(_ file: URL, title: String, videoID: String, directory: URL? = nil) throws -> URL {
        let folder = directory ?? archiveDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let clean = title.components(separatedBy: forbidden).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String((clean.isEmpty ? "YouTube audio" : clean).prefix(100)) + " [" + videoID + "]"
        var destination = folder.appendingPathComponent(base + ".mp3")
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent(base + " (\(number)).mp3"); number += 1
        }
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }
    static func savedCopies(videoID: String, directory: URL? = nil) -> [URL] {
        let legacyArchive = archiveDirectory.deletingLastPathComponent().appendingPathComponent("Yoto Pixel Studio", isDirectory: true)
        let folders = directory.map { [$0] } ?? [archiveDirectory, legacyArchive]
        let files = folders.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        return files.filter {
            let name = $0.deletingPathExtension().lastPathComponent
            return $0.pathExtension.lowercased() == "mp3" && (name.hasSuffix("[" + videoID + "]") || name.contains("[" + videoID + "] ("))
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func youtubeURLs(_ input: String) throws -> [URL] {
        let parts = input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw StudioError("Paste one YouTube video link per line.") }
        var seen = Set<String>()
        return try parts.map { try youtubeURL($0) }.filter { seen.insert($0.absoluteString).inserted }
    }
    static func appendBatch(_ tracks: [(transcode: JSON, title: String)], to card: JSON) throws -> JSON {
        guard !tracks.isEmpty else { throw StudioError("Download at least one track first.") }
        return try tracks.reduce(card) { try append(transcode: $1.transcode, title: $1.title, to: $0) }
    }
    static func youtubeURL(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              url.user == nil, url.password == nil, url.port == nil, let host = url.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"].contains(host) else {
            throw StudioError("Enter a single HTTPS YouTube video link.")
        }
        let parts = url.path.split(separator: "/")
        let id: String?
        if host.hasSuffix("youtu.be") { id = parts.first.map(String.init) }
        else if url.path == "/watch" { id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value }
        else if parts.count == 2 && ["shorts", "live"].contains(String(parts[0])) { id = String(parts[1]) }
        else { id = nil }
        guard let id, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
            throw StudioError("Choose a single YouTube video, not a channel or playlist.")
        }
        return URL(string: "https://www.youtube.com/watch?v=" + id)!
    }
    static func tool(_ name: String) -> URL? {
        let roots = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return roots.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static var missingTools: [String] { ["yt-dlp", "ffmpeg", "ffprobe", "deno"].filter { tool($0) == nil } }
    static func append(transcode: JSON, title: String, to card: JSON) throws -> JSON {
        guard let id = card["cardId"] as? String, !id.isEmpty,
              var content = card["content"] as? JSON, var chapters = content["chapters"] as? [JSON],
              let hash = transcode["transcodedSha256"] as? String, !hash.isEmpty else { throw StudioError("Incomplete playlist or audio conversion response. Nothing was added.") }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StudioError("Give the new track a title.") }
        let info = transcode["transcodedInfo"] as? JSON ?? [:]
        let label = String(chapters.count + 1)
        var track: JSON = ["key": "01", "title": title, "trackUrl": "yoto:#" + hash, "type": "audio", "overlayLabel": label, "uid": hash, "display": [:], "format": "mp3"]
        for field in ["duration", "fileSize", "format"] { if let value = info[field] { track[field] = value } }
        if let channels = info["channels"] as? Int { track["channels"] = channels == 1 ? "mono" : "stereo" }
        else if let channels = info["channels"] as? String { track["channels"] = channels }
        let existingKeys = Set(chapters.compactMap { $0["key"] as? String })
        var chapterKey: String
        repeat { chapterKey = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)) }
        while existingKeys.contains(chapterKey)
        chapters.append(["display": [:], "key": chapterKey, "title": title, "overlayLabel": label, "tracks": [track]])
        content["chapters"] = chapters
        var payload: JSON = ["cardId": id, "content": content, "title": card["title"] ?? "Playlist"]
        if var metadata = card["metadata"] as? JSON {
            // Update known aggregate media values while keeping all unrelated metadata.
            if var media = metadata["media"] as? JSON {
                for field in ["duration", "fileSize"] {
                    if let old = media[field] as? NSNumber, let added = info[field] as? NSNumber { media[field] = old.doubleValue + added.doubleValue }
                }
                media.removeValue(forKey: "readableFileSize")
                metadata["media"] = media
            }
            payload["metadata"] = metadata
        }
        return payload
    }
}

@MainActor
final class AudioDownloader {
    private var process: Process?
    private var cancelled = false
    func cancel() { cancelled = true; if process?.isRunning == true { process?.interrupt() } }
    private func execute(_ executable: URL, _ arguments: [String], directory: URL, logName: String) async throws -> String {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let log = directory.appendingPathComponent(logName)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let job = Process()
        job.executableURL = executable; job.arguments = arguments
        job.currentDirectoryURL = directory
        job.standardOutput = handle; job.standardError = handle; job.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        job.environment = environment
        process = job
        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            job.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try job.run() } catch { job.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        process = nil
        guard !cancelled, !Task.isCancelled else { throw CancellationError() }
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard code == 0 else {
            // Last lines help diagnose extractor/tool errors without collecting browser credentials.
            throw StudioError((text.contains("HTTP Error 403") ? "YouTube refused the audio download. Retry, or update the tools with: brew upgrade yt-dlp deno. Your saved MP3s are kept.\n" : "\(executable.lastPathComponent) could not finish.\n") + text.split(separator: "\n").suffix(5).joined(separator: "\n"))
        }
        return text
    }
    func preparePublic(_ track: PublicAudioTrack, archiveDirectory: URL? = nil, progress: @escaping (String) -> Void) async throws -> PreparedAudio {
        cancelled = false
        guard let ffmpeg = AudioImport.tool("ffmpeg"), let probe = AudioImport.tool("ffprobe") else {
            throw StudioError("Install FFmpeg to import public audio: brew install ffmpeg")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let identity = PublicAudio.stableID(track.url)
            var artwork: [UInt32]?
            var artworkWarning: String?
            if let url = track.artworkURL {
                progress("Loading the original artwork…")
                let image = directory.appendingPathComponent("artwork")
                do {
                    try await PublicAudio.download(url, to: image, maximumBytes: 8 * 1024 * 1024)
                    artwork = try PixelArt.importImage(image)
                } catch { if Task.isCancelled { throw CancellationError() }; artworkWarning = "Original artwork could not be downloaded; audio is still ready." }
            }
            func verify(_ file: URL) async throws -> PreparedAudio {
                let text = try await execute(probe, ["-v", "error", "-show_entries", "stream=codec_name,bit_rate:format=duration", "-of", "json", file.path], directory: directory, logName: "probe-public.json")
                let result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? JSON ?? [:]
                let stream = (result["streams"] as? [JSON] ?? []).first ?? [:]
                let format = result["format"] as? JSON ?? [:]
                guard stream["codec_name"] as? String == "mp3", stream["bit_rate"] as? String == "320000",
                      let duration = Double(format["duration"] as? String ?? ""), duration.isFinite, duration > 0 else {
                    throw StudioError("The public audio did not pass the MP3 check.")
                }
                let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes > 0 else { throw StudioError("The public audio is empty.") }
                return PreparedAudio(url: file, title: track.title, duration: duration, bytes: bytes, bitrate: 320000, directory: directory, artwork: artwork, artworkWarning: artworkWarning)
            }
            for cached in AudioImport.savedCopies(videoID: identity, directory: archiveDirectory) {
                do { progress("Checking a saved MP3…"); return try await verify(cached) }
                catch { if Task.isCancelled || cancelled { throw CancellationError() } }
            }
            progress("Downloading public audio…")
            let source = directory.appendingPathComponent("source.audio")
            try await PublicAudio.download(track.url, to: source)
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            progress("Encoding MP3 at 320 kbps…")
            let output = directory.appendingPathComponent("audio.mp3")
            _ = try await execute(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-protocol_whitelist", "file,pipe", "-i", source.path, "-vn", "-c:a", "libmp3lame", "-b:a", "320k", "-ar", "44100", "-ac", "2", "-map_metadata", "-1", "-metadata", "title=" + track.title, "-y", output.path], directory: directory, logName: "encode-public.log")
            progress("Checking and keeping a local copy…")
            let checked = try await verify(output)
            let copy = try AudioImport.keepLocalCopy(output, title: track.title, videoID: identity, directory: archiveDirectory)
            try? FileManager.default.removeItem(at: source)
            return PreparedAudio(url: copy, title: checked.title, duration: checked.duration, bytes: checked.bytes, bitrate: checked.bitrate, directory: directory, artwork: artwork, artworkWarning: artworkWarning)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func prepare(_ input: String, progress: @escaping (String) -> Void) async throws -> PreparedAudio {
        let url = try AudioImport.youtubeURL(input)
        cancelled = false
        let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
        if let probe = AudioImport.tool("ffprobe") {
            for file in AudioImport.savedCopies(videoID: videoID) {
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-audio-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                do {
                    progress("Checking a saved MP3…")
                    let text = try await execute(probe, ["-v", "error", "-show_entries", "stream=codec_name,bit_rate:format=duration:format_tags=title", "-of", "json", file.path], directory: scratch, logName: "probe.json")
                    let result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? JSON ?? [:]
                    let stream = (result["streams"] as? [JSON] ?? []).first ?? [:]
                    let format = result["format"] as? JSON ?? [:]
                    guard stream["codec_name"] as? String == "mp3", stream["bit_rate"] as? String == "320000",
                          let duration = Double(format["duration"] as? String ?? ""), duration.isFinite, duration > 0 else { throw StudioError("Saved audio needs downloading again.") }
                    let title = (format["tags"] as? JSON)?["title"] as? String ?? file.deletingPathExtension().lastPathComponent
                    let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes > 0 else { throw StudioError("Saved audio is empty.") }
                    return PreparedAudio(url: file, title: title, duration: duration, bytes: bytes, bitrate: 320000, directory: scratch)
                } catch {
                    try? FileManager.default.removeItem(at: scratch)
                    if Task.isCancelled || cancelled { throw CancellationError() }
                }
            }
        }
        guard AudioImport.missingTools.isEmpty,
              let downloader = AudioImport.tool("yt-dlp"), let ffmpeg = AudioImport.tool("ffmpeg"), let probe = AudioImport.tool("ffprobe"), let deno = AudioImport.tool("deno") else {
            throw StudioError("Install the audio tools shown in this window, then click Check tools.")
        }
        cancelled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-audio-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            progress("Downloading the best available source audio…")
            _ = try await execute(downloader, ["--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-progress", "--no-warnings", "--match-filter", "!is_live", "--socket-timeout", "30", "--retries", "3", "--js-runtimes", "deno:" + deno.path, "--check-formats", "--format", "bestaudio", "--write-info-json", "--output", "source.%(ext)s", "--", url.absoluteString], directory: directory, logName: "download.log")
            let infoURL = directory.appendingPathComponent("source.info.json")
            let info = try JSONSerialization.jsonObject(with: Data(contentsOf: infoURL)) as? JSON ?? [:]
            let title = info["title"] as? String ?? "YouTube audio"
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let source = files.first(where: { $0.lastPathComponent.hasPrefix("source.") && !["json", "part", "ytdl"].contains($0.pathExtension) }) else { throw StudioError("The downloader produced no audio file.") }
            progress("Encoding MP3 at 320 kbps…")
            let output = directory.appendingPathComponent("audio.mp3")
            _ = try await execute(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-i", source.path, "-vn", "-c:a", "libmp3lame", "-b:a", "320k", "-ar", "44100", "-ac", "2", "-map_metadata", "-1", "-metadata", "title=" + title, "-y", output.path], directory: directory, logName: "encode.log")
            progress("Checking the MP3…")
            let details = try await execute(probe, ["-v", "error", "-show_entries", "stream=codec_name,bit_rate:format=duration,size", "-of", "json", output.path], directory: directory, logName: "probe.json")
            let result = try JSONSerialization.jsonObject(with: Data(details.utf8)) as? JSON ?? [:]
            let stream = (result["streams"] as? [JSON] ?? []).first ?? [:]
            let format = result["format"] as? JSON ?? [:]
            guard stream["codec_name"] as? String == "mp3", let bitrate = Int(stream["bit_rate"] as? String ?? ""), bitrate == 320000,
                  let duration = Double(format["duration"] as? String ?? ""), duration.isFinite, duration > 0 else { throw StudioError("The encoded MP3 did not pass the 320 kbps audio check.") }
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0 else { throw StudioError("The downloaded audio is empty.") }
            let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value ?? UUID().uuidString
            let localCopy = try AudioImport.keepLocalCopy(output, title: title, videoID: videoID)
            try? FileManager.default.removeItem(at: source)
            return PreparedAudio(url: localCopy, title: title, duration: duration, bytes: bytes, bitrate: bitrate, directory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
