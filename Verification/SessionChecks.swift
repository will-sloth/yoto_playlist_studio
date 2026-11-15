import Foundation

@MainActor private final class MemoryCredentialStore: YotoCredentialStore {
    var value: YotoCredentials?
    var writes = 0, deletes = 0
    var failSave = false
    func load() throws -> YotoCredentials? { value }
    func save(_ credentials: YotoCredentials) throws {
        if failSave { throw StudioError("Simulated Keychain error") }
        value = credentials; writes += 1
    }
    func delete() throws { value = nil; deletes += 1 }
}
private final class AuthProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, JSON))!
    static var delay: TimeInterval = 0.02
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, object) = try Self.handler(request)
            let job = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
                self.client?.urlProtocolDidFinishLoading(self)
            }
            work = job; DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: job)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { work?.cancel() }
}
private final class AuthCounters {
    let lock = NSLock()
    var renewals = 0, calls = 0
}
@main struct SessionChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let api = URLRequest(url: URL(string: "https://api.yotoplay.com/content/mine")!)
        func seeded(expires: Int = 1) throws -> (YotoSession, MemoryCredentialStore) {
            let store = MemoryCredentialStore()
            let auth = YotoSession(session: session, store: store)
            try auth.accept(["access_token": "old-access", "refresh_token": "refresh+one&x=value", "expires_in": expires], clientID: "public-client")
            return (auth, store)
        }
        func configure(_ counts: AuthCounters, rejectOld: Bool = false, rejectAll: Bool = false, refreshStatus: Int = 200, omitRotation: Bool = false) {
            AuthProtocol.handler = { request in
                counts.lock.lock(); defer { counts.lock.unlock() }
                if request.url?.host == "login.yotoplay.com" {
                    precondition(request.url?.path == "/oauth/token" && request.httpMethod == "POST")
                    precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
                    var data = request.httpBody ?? Data()
                    if data.isEmpty, let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 2048)
                        while true { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
                    }
                    let items = URLComponents(string: "?" + String(decoding: data, as: UTF8.self))!.queryItems!
                    precondition(items.first { $0.name == "grant_type" }?.value == "refresh_token")
                    precondition(items.first { $0.name == "client_id" }?.value == "public-client")
                    precondition(items.first { $0.name == "refresh_token" }?.value == "refresh+one&x=value")
                    counts.renewals += 1
                    if refreshStatus != 200 { return (refreshStatus, ["error": refreshStatus == 400 ? "invalid_grant" : "server_error"]) }
                    var result: JSON = ["access_token": "new-access", "expires_in": 3600]
                    if !omitRotation { result["refresh_token"] = "rotated-refresh" }
                    return (200, result)
                }
                counts.calls += 1
                let rejected = rejectAll || (rejectOld && request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
                return (rejected ? 401 : 200, ["cards": [JSON]()])
            }
        }
        let (auth, store) = try seeded()
        let counts = AuthCounters(); configure(counts)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in
                let (_, response) = try await auth.data(for: api)
                precondition((response as! HTTPURLResponse).statusCode == 200)
            } }
            try await group.waitForAll()
        }
        precondition(counts.renewals == 1 && counts.calls == 8 && store.value?.refreshToken == "rotated-refresh")
        let relaunched = YotoSession(session: session, store: store)
        let restored = try await relaunched.restore(clientID: "public-client"); precondition(restored && relaunched.connected)
        _ = try await relaunched.data(for: api)
        precondition(counts.renewals == 1)
        let wrongClient = YotoSession(session: session, store: store)
        let wrongRestore = try await wrongClient.restore(clientID: "another-client"); precondition(!wrongRestore && !wrongClient.connected)
        try relaunched.disconnect(); precondition(store.value == nil && !relaunched.connected)
        print("PASS: renewable sign-in survives relaunch through injected secure storage; parallel requests share one token rotation; client IDs cannot cross-restore; disconnect clears saved credentials")
        let (retry401, _) = try seeded(expires: 3600)
        let retryCounts = AuthCounters(); configure(retryCounts, rejectOld: true)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 { group.addTask { @MainActor in
                let (_, response) = try await retry401.data(for: api); precondition((response as! HTTPURLResponse).statusCode == 200)
            } }
            try await group.waitForAll()
        }
        precondition(retryCounts.renewals == 1 && retryCounts.calls == 12)
        let (once, _) = try seeded(expires: 3600)
        let onceCounts = AuthCounters(); configure(onceCounts, rejectAll: true)
        let (_, unauthorized) = try await once.data(for: api)
        precondition((unauthorized as! HTTPURLResponse).statusCode == 401 && onceCounts.renewals == 1 && onceCounts.calls == 2)
        print("PASS: simultaneous HTTP 401s share renewal and retry once; repeated HTTP 401 cannot loop")
        let (revoked, revokedStore) = try seeded(); configure(AuthCounters(), refreshStatus: 400)
        do { _ = try await revoked.validAccessToken(); fatalError("Revoked session accepted") } catch {}
        precondition(revokedStore.value == nil && !revoked.connected)
        let (temporary, temporaryStore) = try seeded(); configure(AuthCounters(), refreshStatus: 503)
        do { _ = try await temporary.validAccessToken(); fatalError("Server failure ignored") } catch {}
        precondition(temporaryStore.value?.refreshToken == "refresh+one&x=value" && temporary.connected)
        let (incomplete, incompleteStore) = try seeded(); configure(AuthCounters(), omitRotation: true)
        do { _ = try await incomplete.validAccessToken(); fatalError("Missing rotation ignored") } catch {}
        precondition(incompleteStore.value == nil && !incomplete.connected)
        let (failedSave, failedStore) = try seeded(); failedStore.failSave = true; configure(AuthCounters())
        do { _ = try await failedSave.validAccessToken(); fatalError("Persistence failure ignored") } catch {}
        precondition(failedStore.value == nil && !failedSave.connected)
        print("PASS: revocation clears saved sign-in; temporary failure preserves it; incomplete rotation or secure-save failure cannot reuse a consumed refresh token")
        let (logoutDuringRenewal, logoutStore) = try seeded()
        AuthProtocol.delay = 0.2; configure(AuthCounters())
        let pending = Task { @MainActor in try await logoutDuringRenewal.validAccessToken() }
        try await Task.sleep(nanoseconds: 30_000_000)
        try logoutDuringRenewal.disconnect()
        do { _ = try await pending.value; fatalError("Logout race restored a session") } catch {}
        precondition(logoutStore.value == nil && !logoutDuringRenewal.connected && logoutStore.writes == 1)
        AuthProtocol.delay = 0.02
        let temporaryLoginStore = MemoryCredentialStore()
        let temporaryLogin = YotoSession(session: session, store: temporaryLoginStore)
        try temporaryLogin.accept(["access_token": "access-only", "expires_in": 3600], clientID: "public-client", remember: false)
        precondition(temporaryLogin.connected && temporaryLoginStore.value == nil && temporaryLogin.notice == nil)
        print("PASS: session-only sign-in works without saving tokens or requiring renewable access")
        let noRefreshStore = MemoryCredentialStore()
        let noRefresh = YotoSession(session: session, store: noRefreshStore)
        try noRefresh.accept(["access_token": "access-only", "expires_in": 1], clientID: "public-client")
        precondition(noRefresh.notice != nil)
        do { _ = try await noRefresh.validAccessToken(); fatalError("Expired access-only token accepted") } catch {}
        precondition(noRefreshStore.value == nil)
        let now = Date(timeIntervalSince1970: 1000)
        precondition(YotoSession.expiry(["expires_in": 60], accessToken: "opaque", now: now) == now.addingTimeInterval(60))
        let jwtData = try JSONSerialization.data(withJSONObject: ["exp": 12345])
        let jwt = "header." + jwtData.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        precondition(YotoSession.expiry([:], accessToken: jwt)?.timeIntervalSince1970 == 12345)
        print("PASS: logout during renewal cannot resurrect credentials; access-only sessions expire clearly; expiry parsing uses returned lifetime or JWT timing (no real credentials or Keychain touched)")
    }
}
