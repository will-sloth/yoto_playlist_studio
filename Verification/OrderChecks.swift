import Foundation

private final class OrderProtocol: URLProtocol {
    static var card: JSON = [:]
    static var writes = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.httpMethod == "POST" {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
                while true { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
            }
            Self.card = try! JSONSerialization.jsonObject(with: data) as! JSON
            Self.writes += 1
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["card": Self.card]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct OrderChecks {
    @MainActor static func main() async throws {
        let original: JSON = ["cardId": "reorder", "title": "Songs", "updatedAt": "old", "metadata": ["author": "Parent", "media": ["duration": 60, "fileSize": 600]], "content": ["config": ["shuffle": true], "future": "keep", "chapters": [
            ["key": "a", "title": "Grouped", "duration": 30, "fileSize": 300, "display": ["icon16x16": "yoto:#inherited"], "ambient": ["keep": true], "tracks": [
                ["key": "1", "title": "One", "trackUrl": "yoto:#one", "duration": 10, "fileSize": 100, "overlayLabel": "1", "unknownTrack": true],
                ["key": "2", "title": "Two", "trackUrl": "yoto:#two", "duration": 20, "fileSize": 200, "overlayLabel": "2", "display": ["icon16x16": "yoto:#override"]]
            ]],
            ["key": "b", "title": "Single", "tracks": [["key": "1", "title": "Three", "trackUrl": "yoto:#three", "duration": 30, "fileSize": 300, "overlayLabel": "Custom"]]],
            ["key": "empty", "title": "Empty", "tracks": [JSON](), "futureEmpty": true]
        ]]]
        let originalBytes = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        let order = ["0:1", "1:0", "0:0"]
        let payload = try PlaylistOrder.payload(original, order: order)
        precondition(CardEditor.rows(payload).map(\.title) == ["Two", "Three", "One"])
        precondition(CardEditor.rows(payload).map(\.icon) == ["yoto:#override", nil, "yoto:#inherited"])
        let chapters = (payload["content"] as! JSON)["chapters"] as! [JSON]
        precondition(chapters.count == 4 && (chapters.last?["futureEmpty"] as? Bool) == true)
        let keys = chapters.compactMap { $0["key"] as? String }
        precondition(Set(keys).count == keys.count && keys.allSatisfy { $0.count <= 20 })
        precondition((chapters[0]["duration"] as? Double) == 20 && (chapters[2]["duration"] as? Double) == 10)
        let tracks = chapters.flatMap { $0["tracks"] as? [JSON] ?? [] }
        precondition(tracks.map { $0["trackUrl"] as! String } == ["yoto:#two", "yoto:#three", "yoto:#one"])
        precondition(tracks.map { $0["overlayLabel"] as! String } == ["1", "Custom", "3"])
        precondition(tracks.last?["unknownTrack"] as? Bool == true)
        precondition((chapters[0]["ambient"] as! JSON)["keep"] as? Bool == true && (chapters[2]["ambient"] as! JSON)["keep"] as? Bool == true)
        precondition(((payload["content"] as! JSON)["config"] as! JSON)["shuffle"] as? Bool == true)
        precondition(((payload["metadata"] as! JSON)["media"] as! JSON)["duration"] as? Int == 60)
        let unchangedBytes = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        precondition(unchangedBytes == originalBytes)
        let noChange = try PlaylistOrder.payload(original, order: CardEditor.rows(original).map(\.id))
        let noContentChange = try PlaylistOrder.sameContent(original, noChange); precondition(noContentChange)
        let grouped = try PlaylistOrder.payload(original, order: ["0:1", "0:0", "1:0"])
        precondition(((grouped["content"] as! JSON)["chapters"] as! [JSON]).count == 3)
        for bad in [["0:0"], ["0:0", "0:0", "1:0"], ["0:0", "0:1", "9:0"]] {
            do { _ = try PlaylistOrder.payload(original, order: bad); fatalError("Invalid order accepted") } catch {}
        }
        print("PASS: reordering preserves audio, inherited/override artwork, settings, custom labels, total metadata and original data; split chapters have distinct keys and correct totals; adjacent chapter groups stay intact; invalid orders are rejected")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OrderProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let service = YotoService(session: session, accessToken: "fixture-only")
        OrderProtocol.card = original
        OrderProtocol.card["updatedAt"] = "new timestamp"
        OrderProtocol.card["title"] = "Current title"
        OrderProtocol.card["metadata"] = ["author": "Current author"]
        var backedUp = false
        let result = try await service.saveOrder(order, baseline: original) { latest in
            precondition(latest["updatedAt"] as? String == "new timestamp"); backedUp = true
        }
        precondition(OrderProtocol.writes == 1 && backedUp)
        precondition(result["title"] as? String == "Current title" && (result["metadata"] as! JSON)["author"] as? String == "Current author")
        do { _ = try await service.saveOrder(order, baseline: original); fatalError("Conflicting content accepted") } catch {}
        precondition(OrderProtocol.writes == 1)
        OrderProtocol.card = original
        do { _ = try await service.saveOrder(order, baseline: original) { _ in throw StudioError("Backup unavailable") }; fatalError("Backup failure ignored") } catch {}
        precondition(OrderProtocol.writes == 1)
        print("PASS: saving order tolerates timestamp-only changes, keeps current title/metadata, backs up before writing, and blocks stale content or backup failure (simulated Yoto)")
    }
}
