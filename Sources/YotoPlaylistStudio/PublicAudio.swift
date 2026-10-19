import Foundation
import CryptoKit

struct PublicAudioTrack: Identifiable {
    let id: String
    let title: String
    let url: URL
    let artworkURL: URL?
}

struct PublicAudioCollection {
    let title: String
    let tracks: [PublicAudioTrack]
}

enum PublicAudio {
    static let catalogURL = URL(string: "https://yoto.space/public-domain")!
    static func remoteURL(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host != "localhost",
              !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }) else {
            throw StudioError("Use an HTTPS audio link on a public website.")
        }
        return url
    }
    static func shareURL(_ input: String) throws -> URL {
        let url = try remoteURL(input)
        let parts = url.path.split(separator: "/")
        guard url.host?.lowercased() == "share.yoto.co", parts.count == 2, parts[0] == "s",
              parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw StudioError("Paste the Yoto share link from an Add to your library button.")
        }
        return url
    }
    static func stableID(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if url.host?.lowercased() == "secure-media.yotoplay.com" {
            components.queryItems = components.queryItems?.filter { !["Expires", "Signature", "Key-Pair-Id"].contains($0.name) }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
        }
        components.fragment = nil
        let digest = SHA256.hash(data: Data((components.string ?? url.absoluteString).utf8)).map { String(format: "%02x", $0) }.joined()
        return "audio-" + digest.prefix(20)
    }
    static func directTracks(_ input: String) throws -> [PublicAudioTrack] {
        let lines = input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw StudioError("Paste one direct audio-file link per line.") }
        var seen = Set<String>()
        return try lines.map { line in
            let url = try remoteURL(line)
            guard ["mp3", "m4a", "aac", "ogg", "opus", "wav", "flac", "aiff", "aif"].contains(url.pathExtension.lowercased()) else {
                throw StudioError("Choose a direct MP3, M4A, AAC, Ogg, Opus, WAV, FLAC or AIFF file. Use Browse Yoto Space for shared playlists.")
            }
            let title = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Public audio"
            return PublicAudioTrack(id: stableID(url), title: title, url: url, artworkURL: nil)
        }.filter { seen.insert($0.id).inserted }
    }
    static func collection(html: String) throws -> PublicAudioCollection {
        // Read the same publicly delivered playlist data that renders Yoto's share page.
        let pattern = #"<script\b(?=[^>]*\bid\s*=\s*["']__NEXT_DATA__["'])[^>]*>([\s\S]*?)</script\s*>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range), let jsonRange = Range(match.range(at: 1), in: html),
              let root = try JSONSerialization.jsonObject(with: Data(html[jsonRange].utf8)) as? JSON,
              let props = root["props"] as? JSON, let page = props["pageProps"] as? JSON, let card = page["card"] as? JSON,
              let content = card["content"] as? JSON, let chapters = content["chapters"] as? [JSON] else {
            throw StudioError("This share page has no readable public audio. It may have expired or the site may have changed. You can still import direct audio links.")
        }
        var result: [PublicAudioTrack] = []
        for (ci, chapter) in chapters.enumerated() {
            for (ti, track) in (chapter["tracks"] as? [JSON] ?? []).enumerated() {
                guard let address = track["trackUrl"] as? String else { continue }
                let url = try remoteURL(address)
                let trackDisplay = track["display"] as? JSON ?? [:]
                let chapterDisplay = chapter["display"] as? JSON ?? [:]
                let display = (trackDisplay["icon16x16"] as? String)?.isEmpty == false ? trackDisplay : chapterDisplay
                let art = [display["iconUrl16x16"], display["icon16x16"]].compactMap { $0 as? String }.compactMap { try? remoteURL($0) }.first
                result.append(PublicAudioTrack(id: "\(ci):\(ti)", title: track["title"] as? String ?? chapter["title"] as? String ?? "Track \(result.count + 1)", url: url, artworkURL: art))
            }
        }
        guard !result.isEmpty else { throw StudioError("This shared playlist has no downloadable public audio files.") }
        // Only return the title and media needed for import, never creator/account metadata.
        return PublicAudioCollection(title: card["title"] as? String ?? "Public audio", tracks: result)
    }
    static func loadCollection(_ input: String) async throws -> PublicAudioCollection {
        let url = try shareURL(input)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-share-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try await download(url, to: temp, maximumBytes: 8 * 1024 * 1024)
        return try collection(html: String(contentsOf: temp, encoding: .utf8))
    }
    static func download(_ url: URL, to destination: URL, maximumBytes: Int = 512 * 1024 * 1024) async throws {
        _ = try remoteURL(url.absoluteString)
        let policy = PublicAudioRedirects()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: policy, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(for: URLRequest(url: url))
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StudioError("The public audio source could not be downloaded (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Reopen the shared playlist if its links expired.")
        }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw StudioError("The source file is empty or larger than the \(maximumBytes / 1024 / 1024) MB import limit.") }
        try FileManager.default.moveItem(at: file, to: destination)
    }
}

private final class PublicAudioRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { try? PublicAudio.remoteURL($0.absoluteString) } == nil ? nil : request)
    }
}
