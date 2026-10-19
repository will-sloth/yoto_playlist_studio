import Foundation

private final class StubYotoProtocol: URLProtocol {
    static var delay: TimeInterval = 0
    static var finished: (() -> Void)?
    static var handler: ((URLRequest) throws -> (Int, JSON))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, object) = try Self.handler!(request)
            let deliver = {
                let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
                Self.finished?()
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if Self.delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: deliver) }
            else { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class TransferProbe {
    let lock = NSLock()
    var active = 0, peak = 0, puts = 0
    func start(put: Bool) { lock.lock(); defer { lock.unlock() }; active += 1; peak = max(peak, active); if put { puts += 1 } }
    func finish() { lock.lock(); defer { lock.unlock() }; active -= 1 }
}

@main struct ServiceChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubYotoProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = YotoService(session: session, accessToken: "test-only-token")
        var requests = 0
        StubYotoProtocol.handler = { request in
            requests += 1
            precondition(request.httpMethod == "POST" && request.url?.path == "/content")
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
            }
            var body = try JSONSerialization.jsonObject(with: bytes) as! JSON
            precondition(body["cardId"] == nil && body["title"] as? String == "Public stories")
            let chapters = (body["content"] as! JSON)["chapters"] as! [JSON]
            precondition(chapters.count == 1)
            precondition((chapters[0]["tracks"] as! [JSON])[0]["trackUrl"] as? String == "yoto:#processed-audio")
            body["cardId"] = "new-playlist-id"
            return (200, ["card": body])
        }
        var draft = try CardEditor.newPlaylist(title: "Public stories")
        do { _ = try await service.createPlaylist(draft); fatalError("Empty creation should fail") } catch { precondition(requests == 0) }
        draft["cardId"] = "local-draft"
        var payload = try AudioImport.append(transcode: ["transcodedSha256": "processed-audio", "transcodedInfo": ["duration": 30, "fileSize": 100, "format": "mp3"]], title: "First story", to: draft)
        payload.removeValue(forKey: "cardId")
        let saved = try await service.createPlaylist(payload)
        precondition(saved["cardId"] as? String == "new-playlist-id" && requests == 1)
        print("PASS: first-track playlist creation posts no old card ID, rejects empty creation, and returns the new server ID")
        StubYotoProtocol.handler = { request in
            precondition(request.url?.path == "/media/displayIcons/user/me")
            return (200, ["displayIcons": [["mediaId": "private-icon", "title": "Original artwork", "url": "https://example.com/icon.png"]]])
        }
        let icons = try await service.icons(owned: true)
        precondition(icons.first?.id == "private-icon" && icons.first?.url?.host == "example.com")
        print("PASS: custom icon library requests the user endpoint and decodes image URLs")
        StubYotoProtocol.handler = { _ in (400, ["message": "Validation detail"]) }
        do { _ = try await service.createPlaylist(payload); fatalError("Expected API failure") }
        catch { precondition(error.localizedDescription.contains("Creating the playlist") && error.localizedDescription.contains("Validation detail")) }
        print("PASS: playlist creation failure retains the server reason and creation step")
        let probe = TransferProbe()
        StubYotoProtocol.delay = 0.03
        StubYotoProtocol.finished = { probe.finish() }
        StubYotoProtocol.handler = { request in
            let isPut = request.httpMethod == "PUT"
            probe.start(put: isPut)
            if isPut {
                precondition(request.url?.host == "upload.example.test")
                precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
                return (200, [:])
            }
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-token")
            if request.url?.path == "/media/transcode/audio/uploadUrl" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let checksum = query.first { $0.name == "sha256" }!.value!
                let id = String(checksum.prefix(20))
                return (200, ["upload": ["uploadId": id, "uploadUrl": "https://upload.example.test/" + id]])
            }
            let parts = request.url!.path.split(separator: "/")
            precondition(parts.count == 4 && parts[0] == "media" && parts[1] == "upload" && parts[3] == "transcoded")
            return (200, ["transcode": ["transcodedSha256": "audio-" + parts[2], "transcodedInfo": ["duration": 1, "format": "mp3"]]])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-parallel-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var hashes = [String?](repeating: nil, count: 4)
        var failures: [String] = []
        await ParallelAudio.run(indices: Array(0..<4), limit: 2) { index in
            do {
                let file = directory.appendingPathComponent("track-\(index).mp3")
                try Data("audio-fixture-\(index)".utf8).write(to: file)
                let response = try await service.uploadAudio(file) { _ in }
                hashes[index] = response["transcodedSha256"] as? String
            } catch { failures.append(error.localizedDescription) }
        }
        precondition(failures.isEmpty && hashes.allSatisfy { $0 != nil })
        precondition(Set(hashes.compactMap { $0 }).count == 4)
        precondition(probe.peak == 2 && probe.puts == 4 && probe.active == 0)
        StubYotoProtocol.delay = 0; StubYotoProtocol.finished = nil
        print("PASS: real upload service overlaps two signed uploads and processing polls, keeps results distinct, and never forwards Yoto authorization to storage (simulated responses)")
    }
}
