import Foundation

@main struct TrimChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-trim-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("original.mp3")
        let job = Process()
        job.executableURL = AudioImport.tool("ffmpeg")!
        job.arguments = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "3", "-c:a", "libmp3lame", "-b:a", "320k", file.path]
        try job.run(); job.waitUntilExit(); precondition(job.terminationStatus == 0)
        let original = try Data(contentsOf: file)
        let audio = PreparedAudio(url: file, title: "Test original", duration: 3, bytes: original.count, bitrate: 320000, directory: directory, artwork: [UInt32](repeating: 0, count: 256))
        let downloader = AudioDownloader()
        let trimmed = try await downloader.trim(audio, maximumDuration: 1, archiveDirectory: directory)
        precondition(trimmed.duration > 0 && trimmed.duration <= 1.1)
        precondition(trimmed.url != file && trimmed.bitrate == 320000 && trimmed.artwork == audio.artwork)
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == original)
        let second = try await downloader.trim(audio, maximumDuration: 1, archiveDirectory: directory)
        precondition(second.url != trimmed.url && FileManager.default.fileExists(atPath: trimmed.url.path))
        let cancelled = AudioDownloader(); cancelled.cancel()
        do { _ = try await cancelled.trim(audio, maximumDuration: 1, archiveDirectory: directory); fatalError("Expected cancellation") }
        catch is CancellationError {}
        print("PASS: real MP3 trimming verifies duration/bitrate, preserves originals and artwork, avoids overwrites, and respects cancellation")
    }
}
