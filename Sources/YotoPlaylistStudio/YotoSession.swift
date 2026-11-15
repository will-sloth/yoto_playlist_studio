import Foundation
import Security

struct YotoCredentials: Codable {
    let clientID: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

@MainActor protocol YotoCredentialStore {
    func load() throws -> YotoCredentials?
    func save(_ credentials: YotoCredentials) throws
    func delete() throws
}

@MainActor struct YotoKeychainStore: YotoCredentialStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.yotopixelstudio.yoto-session",
         kSecAttrAccount as String: "signed-in-user",
         kSecAttrSynchronizable as String: false]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw StudioError("Could not access the saved Yoto sign-in in macOS Keychain (\(status)). Unlock your Keychain and try again.") }
    }
    func load() throws -> YotoCredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data else { throw StudioError("The saved Yoto sign-in could not be read. Disconnect and sign in again.") }
        do { return try JSONDecoder().decode(YotoCredentials.self, from: data) }
        catch { throw StudioError("The saved Yoto sign-in is unreadable. Disconnect and sign in again.") }
    }
    func save(_ credentials: YotoCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; values.forEach { item[$0.key] = $0.value }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}

@MainActor final class YotoSession {
    private let session: URLSession
    private let store: any YotoCredentialStore
    private var credentials: YotoCredentials?
    private var generation = UUID()
    private var remembering = false
    private var renewal: (id: UUID, task: Task<String, Error>)?
    var accessToken: String { credentials?.accessToken ?? "" }
    var connected: Bool { credentials != nil }
    var notice: String? {
        guard remembering, let credentials, credentials.refreshToken == nil else { return nil }
        return "Yoto did not issue a renewable sign-in. This session can be remembered until it expires; enable refresh tokens/offline access for your public client and sign in again to stay connected longer."
    }
    init(session: URLSession, accessToken: String = "", store: any YotoCredentialStore) {
        self.session = session; self.store = store
        // Injectable access tokens are only for an existing in-memory session/test;
        // never read or write Keychain implicitly during service initialization.
        if !accessToken.isEmpty { credentials = YotoCredentials(clientID: "", accessToken: accessToken, refreshToken: nil, expiresAt: nil) }
    }
    private func clearMemory() {
        generation = UUID(); renewal?.task.cancel(); renewal = nil; credentials = nil; remembering = false
    }
    func disconnect() throws { clearMemory(); try store.delete() }
    func restore(clientID: String) async throws -> Bool {
        guard !clientID.isEmpty, let saved = try store.load(), saved.clientID == clientID else { return false }
        guard !saved.accessToken.isEmpty else { try store.delete(); return false }
        clearMemory(); credentials = saved; remembering = true
        _ = try await validAccessToken()
        return true
    }
    static func expiry(_ result: JSON, accessToken: String, now: Date = Date()) -> Date? {
        if let seconds = (result["expires_in"] as? NSNumber)?.doubleValue ?? Double(result["expires_in"] as? String ?? ""), seconds.isFinite, seconds > 0 {
            return now.addingTimeInterval(seconds)
        }
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let object = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              let exp = (object["exp"] as? NSNumber)?.doubleValue, exp.isFinite, exp > 0 else { return nil }
        // Used only to schedule renewal; the API still validates the token itself.
        return Date(timeIntervalSince1970: exp)
    }
    func accept(_ result: JSON, clientID: String, remember: Bool = true) throws {
        guard let access = result["access_token"] as? String, !access.isEmpty else { throw StudioError("Yoto returned no access token.") }
        let refresh = (result["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let next = YotoCredentials(clientID: clientID, accessToken: access, refreshToken: refresh, expiresAt: Self.expiry(result, accessToken: access))
        clearMemory()
        // A failed secure save never falls back to a plaintext file/preferences.
        do { if remember { try store.save(next) } else { try store.delete() }; credentials = next; remembering = remember }
        catch { try? store.delete(); throw error }
    }
    func validAccessToken(rejected: String? = nil) async throws -> String {
        guard let current = credentials else { throw StudioError("Connect your Yoto account first.") }
        if let rejected, rejected != current.accessToken { return current.accessToken }
        let expiring = current.expiresAt.map { $0.timeIntervalSinceNow <= 30 } ?? false
        if rejected == nil && !expiring { return current.accessToken }
        guard let refresh = current.refreshToken, !refresh.isEmpty else {
            let removeSaved = remembering
            clearMemory(); if removeSaved { try store.delete() }
            throw StudioError("Your saved Yoto sign-in expired. Sign in again to enable automatic renewal.")
        }
        if let existing = renewal {
            let version = generation
            let access = try await existing.task.value
            guard generation == version, credentials?.accessToken == access else { throw CancellationError() }
            return access
        }
        let id = UUID(), version = generation, saveRenewed = remembering
        let task = Task { @MainActor in
            var request = URLRequest(url: URL(string: "https://login.yotoplay.com/oauth/token")!)
            request.httpMethod = "POST"; request.timeoutInterval = 30
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = ["grant_type": "refresh_token", "client_id": current.clientID, "refresh_token": refresh].map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            let (data, response) = try await self.session.data(for: request)
            guard self.generation == version, !Task.isCancelled else { throw CancellationError() }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
            guard (200..<300).contains(status) else {
                if result["error"] as? String == "invalid_grant" || status == 401 {
                    self.clearMemory(); if saveRenewed { try self.store.delete() }
                    throw StudioError("Yoto’s saved sign-in has expired or was revoked. Sign in again.")
                }
                // Keep the saved session for network/server failures; no secrets from
                // the token endpoint's response are displayed or written to logs.
                throw StudioError("Could not renew your Yoto sign-in (HTTP \(status)). Your saved sign-in is kept; try again when connected.")
            }
            guard let access = result["access_token"] as? String, !access.isEmpty,
                  let rotated = result["refresh_token"] as? String, !rotated.isEmpty else {
                self.clearMemory(); if saveRenewed { try self.store.delete() }
                throw StudioError("Yoto did not return a complete renewed sign-in. Please sign in again.")
            }
            let next = YotoCredentials(clientID: current.clientID, accessToken: access, refreshToken: rotated, expiresAt: Self.expiry(result, accessToken: access))
            do { if saveRenewed { try self.store.save(next) } }
            catch {
                // The old refresh token was consumed. Never keep/retry it on disk.
                self.clearMemory(); try? self.store.delete(); throw error
            }
            self.credentials = next
            return access
        }
        renewal = (id, task)
        defer { if renewal?.id == id { renewal = nil } }
        let access = try await task.value
        guard generation == version, credentials?.accessToken == access else { throw CancellationError() }
        return access
    }
    func data(for original: URLRequest) async throws -> (Data, URLResponse) {
        let access = try await validAccessToken()
        var request = original
        request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        let result = try await session.data(for: request)
        guard (result.1 as? HTTPURLResponse)?.statusCode == 401 else { return result }
        let renewed = try await validAccessToken(rejected: access)
        request.setValue("Bearer " + renewed, forHTTPHeaderField: "Authorization")
        // Exactly one retry. Storage URLs use a separate session.upload path.
        return try await session.data(for: request)
    }
}
