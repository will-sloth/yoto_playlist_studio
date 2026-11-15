import Foundation

private final class MoveProtocol: URLProtocol {
    static var cards: [String: JSON] = [:]
    static var writes: [String] = []
    static var changeSourceDuringCopy = false
    static var omitCopiedTracks = false
    static var failSource = false
    static var failDestination = false
    static var loseDestinationResponse = false
    static var loseSourceResponse = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var code = 200, object: JSON
        if request.httpMethod == "POST" {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
                while true { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
            }
            let card = try! JSONSerialization.jsonObject(with: data) as! JSON, id = card["cardId"] as! String
            Self.writes.append(id)
            if (id == "source" && Self.failSource) || (id == "target" && Self.failDestination) {
                code = 400; object = ["message": "simulated save failure"]
            } else {
                Self.cards[id] = card; object = ["card": card]
                if id == "target", Self.changeSourceDuringCopy { Self.cards["source"]?["title"] = "Edited elsewhere during copy" }
                if id == "target", Self.omitCopiedTracks {
                    var content = card["content"] as! JSON
                    content["chapters"] = Array((content["chapters"] as! [JSON]).prefix(1))
                    Self.cards[id]?["content"] = content
                }
                if (id == "target" && Self.loseDestinationResponse) || (id == "source" && Self.loseSourceResponse) {
                    Self.loseDestinationResponse = false; Self.loseSourceResponse = false
                    client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return
                }
            }
        } else {
            object = ["card": Self.cards[request.url!.lastPathComponent]!]
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct MoveChecks {
    @MainActor static func main() async throws {
        let source: JSON = ["cardId": "source", "title": "Original", "metadata": ["author": "Parent", "media": ["duration": 30, "fileSize": 300]], "content": ["config": ["shuffle": true], "future": true, "chapters": [
            ["key": "chapter1", "title": "Two songs", "display": ["icon16x16": "yoto:#inherited", "custom": true], "ambient": ["color": "blue"], "tracks": [
                ["key": "t1", "title": "First", "trackUrl": "yoto:#audio1", "duration": 10, "fileSize": 100, "futureTrack": true],
                ["key": "t2", "title": "Second", "trackUrl": "yoto:#audio2", "duration": 20, "fileSize": 200, "display": ["icon16x16": "yoto:#override"]]
            ]]
        ]]]
        let target: JSON = ["cardId": "target", "title": "Destination", "content": ["chapters": [["key": "existing", "title": "Existing", "tracks": [["key": "old", "trackUrl": "yoto:#old"]]]], "config": ["resumeTimeout": 99]]]
        let plan = try PlaylistMovePlan(source: source, destination: target, selected: ["0:0"])
        precondition(CardEditor.rows(plan.sourceAfter).map(\.title) == ["Second"])
        precondition(CardEditor.rows(plan.destinationAfter).map(\.title) == ["Existing", "First"])
        precondition(CardEditor.rows(plan.destinationAfter).last?.icon == "yoto:#inherited")
        precondition((plan.addedChapters[0]["key"] as! String).count <= 20)
        let movedTrack = (plan.addedChapters[0]["tracks"] as! [JSON])[0]
        precondition(movedTrack["trackUrl"] as? String == "yoto:#audio1" && movedTrack["futureTrack"] as? Bool == true)
        precondition(((plan.sourceAfter["metadata"] as! JSON)["media"] as! JSON)["duration"] as? Double == 20)
        let all = try PlaylistMovePlan(source: source, destination: target, selected: ["0:0", "0:1"])
        precondition(CardEditor.rows(all.sourceAfter).isEmpty)
        precondition(CardEditor.rows(all.destinationAfter).suffix(2).map(\.title) == ["First", "Second"])
        precondition(CardEditor.rows(all.destinationAfter).last?.icon == "yoto:#override")
        do { _ = try PlaylistMovePlan(source: source, destination: source, selected: ["0:0"]); fatalError("Same playlist accepted") } catch {}
        do { _ = try PlaylistMovePlan(source: source, destination: target, selected: ["9:0"]); fatalError("Stale selection accepted") } catch {}
        print("PASS: moves preserve audio, inherited/explicit artwork, unknown fields, ordering, short keys, remaining tracks and totals; same-playlist/stale selections rejected")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MoveProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let service = YotoService(session: session, accessToken: "fixture-only")
        func reset() {
            MoveProtocol.cards = ["source": source, "target": target]; MoveProtocol.writes = []
            MoveProtocol.changeSourceDuringCopy = false; MoveProtocol.omitCopiedTracks = false
            MoveProtocol.failSource = false; MoveProtocol.failDestination = false
            MoveProtocol.loseDestinationResponse = false; MoveProtocol.loseSourceResponse = false
        }
        reset()
        _ = try await PlaylistMover(plan: plan).perform(service: service) { _ in }
        precondition(MoveProtocol.writes == ["target", "source"])
        reset(); MoveProtocol.failDestination = true
        do { _ = try await PlaylistMover(plan: plan).perform(service: service) { _ in }; fatalError("Expected failure") } catch {}
        precondition(MoveProtocol.writes == ["target"])
        precondition(trySame(MoveProtocol.cards["source"]!, source))
        reset(); MoveProtocol.failSource = true
        let retry = PlaylistMover(plan: plan)
        do { _ = try await retry.perform(service: service) { _ in }; fatalError("Expected failure") } catch {}
        MoveProtocol.failSource = false
        _ = try await retry.perform(service: service) { _ in }
        precondition(MoveProtocol.writes == ["target", "source", "source"])
        reset(); MoveProtocol.loseDestinationResponse = true
        let uncertainCopy = PlaylistMover(plan: plan)
        do { _ = try await uncertainCopy.perform(service: service) { _ in }; fatalError("Expected failure") } catch {}
        _ = try await uncertainCopy.perform(service: service) { _ in }
        precondition(MoveProtocol.writes == ["target", "source"])
        reset(); MoveProtocol.loseSourceResponse = true
        let uncertainRemoval = PlaylistMover(plan: plan)
        do { _ = try await uncertainRemoval.perform(service: service) { _ in }; fatalError("Expected failure") } catch {}
        _ = try await uncertainRemoval.perform(service: service) { _ in }
        precondition(MoveProtocol.writes == ["target", "source"])
        reset(); MoveProtocol.omitCopiedTracks = true
        do { _ = try await PlaylistMover(plan: plan).perform(service: service) { _ in }; fatalError("Unconfirmed copy must block removal") } catch {}
        precondition(MoveProtocol.writes == ["target"])
        precondition(trySame(MoveProtocol.cards["source"]!, source))
        reset(); MoveProtocol.changeSourceDuringCopy = true
        do { _ = try await PlaylistMover(plan: plan).perform(service: service) { _ in }; fatalError("Concurrent source edit must block removal") } catch {}
        precondition(MoveProtocol.writes == ["target"])
        reset(); MoveProtocol.cards["source"]?["title"] = "Changed elsewhere"
        do { _ = try await PlaylistMover(plan: plan).perform(service: service) { _ in }; fatalError("Expected stale failure") } catch {}
        precondition(MoveProtocol.writes.isEmpty)
        print("PASS: destination saves first; failed copy never removes originals; retries reconcile failed removal and lost responses without duplicate copies; stale edits block writes (simulated Yoto)")
    }
    static func trySame(_ lhs: JSON, _ rhs: JSON) -> Bool { (try? PlaylistMovePlan.same(lhs, rhs)) == true }
}
