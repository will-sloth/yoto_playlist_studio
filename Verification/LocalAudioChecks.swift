import Foundation

@main struct LocalAudioChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-local-check-" + UUID().uuidString)
        let archive = directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func fixture(_ name: String, title: String?) throws -> URL {
            let file = directory.appendingPathComponent(name + ".mp3")
            let job = Process(); job.executableURL = AudioImport.tool("ffmpeg")!
            var args = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "3", "-c:a", "libmp3lame", "-b:a", "128k"]
            if let title { args += ["-metadata", "title=" + title] }
            args.append(file.path); job.arguments = args
            try job.run(); job.waitUntilExit(); precondition(job.terminationStatus == 0)
            return file
        }
        let source = try fixture("Filename fallback", title: nil)
        let original = try Data(contentsOf: source)
        let first = try await AudioDownloader().prepareLocal(source, archiveDirectory: archive) { _ in }
        defer { try? FileManager.default.removeItem(at: first.directory) }
        precondition(first.title == "Filename fallback" && first.bitrate == 128000 && first.duration > 2.9)
        precondition(first.url != source && first.url.deletingLastPathComponent().path == archive.path)
        let copied = try Data(contentsOf: first.url); precondition(copied == original)
        let unchanged = try Data(contentsOf: source); precondition(unchanged == original)
        let second = try await AudioDownloader().prepareLocal(source, archiveDirectory: archive) { _ in }
        defer { try? FileManager.default.removeItem(at: second.directory) }
        precondition(second.url != first.url && FileManager.default.fileExists(atPath: first.url.path))
        let tagged = try fixture("Other filename", title: "Embedded title")
        let third = try await AudioDownloader().prepareLocal(tagged, archiveDirectory: archive) { _ in }
        defer { try? FileManager.default.removeItem(at: third.directory) }
        precondition(third.title == "Embedded title")
        let trimmed = try await AudioDownloader().trim(first, maximumDuration: 1, archiveDirectory: archive)
        precondition(trimmed.duration < 1.1 && trimmed.bitrate == 128000)
        let afterTrim = try Data(contentsOf: source); precondition(afterTrim == original)
        let bad = directory.appendingPathComponent("broken.mp3")
        try Data("Not audio".utf8).write(to: bad)
        let count = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).count
        do { _ = try await AudioDownloader().prepareLocal(bad, archiveDirectory: archive) { _ in }; fatalError("Invalid MP3 accepted") } catch {}
        do { _ = try await AudioDownloader().prepareLocal(URL(string: "https://example.com/test.mp3")!, archiveDirectory: archive) { _ in }; fatalError("Remote URL accepted") } catch {}
        let task = Task { @MainActor in try await AudioDownloader().prepareLocal(source, archiveDirectory: archive) { _ in } }
        task.cancel()
        do { _ = try await task.value; fatalError("Cancelled import accepted") } catch is CancellationError {}
        let finalCount = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).count
        precondition(finalCount == count)
        print("PASS: local MP3 import preserves original bytes/bitrate, saves distinct copies, reads embedded/fallback titles, supports 128 kbps trimming, rejects invalid/remote inputs and respects cancellation")
    }
}
