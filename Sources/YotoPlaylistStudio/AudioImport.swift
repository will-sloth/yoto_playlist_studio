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
    static func mediaURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: value)?.host?.lowercased(), ["soundcloud.com", "www.soundcloud.com", "m.soundcloud.com"].contains(host) {
            return try soundcloudURL(value)
        }
        return try youtubeURL(value)
    }
    static func soundcloudURL(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              url.user == nil, url.password == nil, url.port == nil,
              ["soundcloud.com", "www.soundcloud.com", "m.soundcloud.com"].contains(url.host?.lowercased() ?? "") else {
            throw StudioError("Enter a full HTTPS SoundCloud track link, such as soundcloud.com/artist/track.")
        }
        let parts = url.path.split(separator: "/").map(String.init)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.contains("%") ?? true),
              !url.path.contains("//"), parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              !["sets", "tracks", "albums", "likes", "reposts", "popular-tracks"].contains(parts[1]),
              !["discover", "search", "charts", "you", "stream", "stations"].contains(parts[0]),
              !(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "secret_token" } ?? false) else {
            throw StudioError("Choose a public SoundCloud track link, not a profile, set, private link or playlist.")
        }
        return URL(string: "https://soundcloud.com/" + parts.joined(separator: "/"))!
    }
    static func mediaURLs(_ input: String) throws -> [URL] {
        let parts = input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw StudioError("Paste one YouTube or SoundCloud track link per line.") }
        var seen = Set<String>()
        return try parts.map { try mediaURL($0) }.filter { seen.insert($0.absoluteString).inserted }
    }
    static func mediaID(_ url: URL) -> String {
        if url.host == "soundcloud.com" { return "soundcloud-" + PublicAudio.stableID(url) }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value ?? PublicAudio.stableID(url)
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
            throw StudioError((text.contains("HTTP Error 403") ? "The audio source refused the download after retrying with a fresh link. Try again later, or use a direct audio link. Your saved MP3s are kept.\n" : "\(executable.lastPathComponent) could not finish.\n") + text.split(separator: "\n").suffix(5).joined(separator: "\n"))
        }
        return text
    }
    func prepareLocal(_ file: URL, archiveDirectory: URL? = nil, progress: @escaping (String) -> Void) async throws -> PreparedAudio {
        cancelled = false
        guard file.isFileURL, file.pathExtension.lowercased() == "mp3" else { throw StudioError("Choose a local MP3 file.") }
        guard let probe = AudioImport.tool("ffprobe") else { throw StudioError("Install FFmpeg to check local audio: brew install ffmpeg") }
        let accessed = file.startAccessingSecurityScopedResource()
        defer { if accessed { file.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-local-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw StudioError("Choose a regular MP3 file.") }
            progress("Copying local MP3…")
            let copy = directory.appendingPathComponent("source.mp3")
            try FileManager.default.copyItem(at: file, to: copy)
            progress("Checking local MP3…")
            let text = try await execute(probe, ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name,bit_rate:format=duration,bit_rate:format_tags=title", "-of", "json", copy.path], directory: directory, logName: "probe.json")
            let info = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? JSON ?? [:]
            let stream = (info["streams"] as? [JSON])?.first ?? [:]
            let format = info["format"] as? JSON ?? [:]
            let bytes = try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard stream["codec_name"] as? String == "mp3", bytes > 0,
                  let duration = Double(format["duration"] as? String ?? ""), duration.isFinite, duration > 0 else {
                throw StudioError("This file is not a readable MP3 with a valid duration. Your original file is unchanged.")
            }
            let tag = ((format["tags"] as? JSON)?["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = tag.isEmpty ? file.deletingPathExtension().lastPathComponent : tag
            let bitrate = Int(stream["bit_rate"] as? String ?? format["bit_rate"] as? String ?? "") ?? 0
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            let saved = try AudioImport.keepLocalCopy(copy, title: title, videoID: PublicAudio.stableID(file), directory: archiveDirectory)
            try FileManager.default.removeItem(at: copy)
            return PreparedAudio(url: saved, title: title, duration: duration, bytes: bytes, bitrate: bitrate, directory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func trim(_ audio: PreparedAudio, maximumDuration: Double = 7199, archiveDirectory: URL? = nil) async throws -> PreparedAudio {
        guard maximumDuration > 0, maximumDuration < 7200, maximumDuration.isFinite,
              let ffmpeg = AudioImport.tool("ffmpeg"), let probe = AudioImport.tool("ffprobe") else {
            throw StudioError("Install FFmpeg to trim audio. Your original MP3 is kept.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-trim-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let output = directory.appendingPathComponent("trimmed.mp3")
            // MP3 frame copying avoids quality loss and keeps trimming fast.
            _ = try await execute(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-i", audio.url.path, "-t", String(maximumDuration), "-map", "0:a:0", "-c:a", "copy", "-y", output.path], directory: directory, logName: "trim.log")
            let text = try await execute(probe, ["-v", "error", "-show_entries", "stream=codec_name,bit_rate:format=duration", "-of", "json", output.path], directory: directory, logName: "probe.json")
            let info = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? JSON ?? [:]
            let stream = (info["streams"] as? [JSON])?.first ?? [:]
            guard let format = info["format"] as? JSON, let duration = Double(format["duration"] as? String ?? ""),
                  duration.isFinite, duration > 0, duration < 7200, duration <= maximumDuration + 0.1,
                  stream["codec_name"] as? String == "mp3" else {
                throw StudioError("The trimmed MP3 did not pass verification. Your original is kept; nothing was uploaded.")
            }
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            let copy = try AudioImport.keepLocalCopy(output, title: audio.title + " (trimmed)", videoID: PublicAudio.stableID(audio.url) + "-trim", directory: archiveDirectory)
            let bytes = try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try? FileManager.default.removeItem(at: directory)
            return PreparedAudio(url: copy, title: audio.title, duration: duration, bytes: bytes, bitrate: Int(stream["bit_rate"] as? String ?? "") ?? audio.bitrate, directory: audio.directory, artwork: audio.artwork, artworkWarning: audio.artworkWarning)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
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
    func prepare(_ input: String, archiveDirectory: URL? = nil, progress: @escaping (String) -> Void) async throws -> PreparedAudio {
        let url = try AudioImport.mediaURL(input)
        let isYouTube = url.host != "soundcloud.com"
        cancelled = false
        let videoID = AudioImport.mediaID(url)
        if let probe = AudioImport.tool("ffprobe") {
            for file in AudioImport.savedCopies(videoID: videoID, directory: archiveDirectory) {
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
        guard let downloader = AudioImport.tool("yt-dlp"), let ffmpeg = AudioImport.tool("ffmpeg"), let probe = AudioImport.tool("ffprobe"),
              !isYouTube || AudioImport.tool("deno") != nil else {
            throw StudioError("Install the audio tools shown in this window, then click Check tools.")
        }
        cancelled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-audio-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            progress("Downloading the best available source audio…")
            // A 403 can be transient or caused by a stale signed media URL. Run a
            // fresh extraction once, and never reuse partial data from that attempt.
            var arguments = ["--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-progress", "--no-warnings", "--match-filter", "!is_live", "--socket-timeout", "30", "--retries", "3", "--check-formats", "--format", "bestaudio", "--write-info-json", "--output", "source.%(ext)s", "--", url.absoluteString]
            if isYouTube, let deno = AudioImport.tool("deno") { arguments.insert(contentsOf: ["--js-runtimes", "deno:" + deno.path], at: 0) }
            for attempt in 0..<2 {
                do {
                    _ = try await execute(downloader, arguments, directory: directory, logName: "download-\(attempt + 1).log")
                    break
                } catch {
                    guard attempt == 0, !cancelled, !Task.isCancelled,
                          let log = try? String(contentsOf: directory.appendingPathComponent("download-1.log"), encoding: .utf8),
                          log.contains("HTTP Error 403") else { throw error }
                    progress("The source refused the link. Getting a fresh download link…")
                    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                        where file.lastPathComponent.hasPrefix("source.") {
                        try FileManager.default.removeItem(at: file)
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            let infoURL = directory.appendingPathComponent("source.info.json")
            let info = try JSONSerialization.jsonObject(with: Data(contentsOf: infoURL)) as? JSON ?? [:]
            let title = info["title"] as? String ?? "Audio"
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
            let localCopy = try AudioImport.keepLocalCopy(output, title: title, videoID: videoID, directory: archiveDirectory)
            try? FileManager.default.removeItem(at: source)
            return PreparedAudio(url: localCopy, title: title, duration: duration, bytes: bytes, bitrate: bitrate, directory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
