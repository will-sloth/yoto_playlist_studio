import Foundation
import Network
import CryptoKit
import AppKit

@MainActor
final class YotoService: NSObject {
    private let authorization: YotoSession
    private var token: String { authorization.accessToken }
    private let session: URLSession
    init(session: URLSession = .shared, accessToken: String = "", credentialStore: (any YotoCredentialStore)? = nil) {
        self.session = session; self.authorization = YotoSession(session: session, accessToken: accessToken, store: credentialStore ?? YotoKeychainStore())
        super.init()
    }
    private var loginAttempt = UUID()
    private var listener: NWListener?
    private var loginContinuation: CheckedContinuation<URL, Error>?
    private var loginTimeout: Task<Void, Never>?
    var connected: Bool { authorization.connected }
    var sessionNotice: String? { authorization.notice }
    func restoreSession(clientID: String) async throws -> Bool { try await authorization.restore(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private func finishLogin(_ result: Result<URL, Error>) {
        guard let continuation = loginContinuation else { return }
        loginContinuation = nil
        listener?.cancel(); listener = nil
        loginTimeout?.cancel(); loginTimeout = nil
        continuation.resume(with: result)
    }
    func cancelLogin() { loginAttempt = UUID(); finishLogin(.failure(CancellationError())) }
    func disconnect() throws { cancelLogin(); try authorization.disconnect() }
    static func authorizationURL(clientID: String, challenge: String, state: String, staySignedIn: Bool) throws -> URL {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, clientID.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains) else {
            throw StudioError("Enter the Client ID from your Yoto public app, rather than a URL, client secret or copied label. Check the developer dashboard if Yoto shows an error before the login form.")
        }
        var url = URLComponents(string: "https://login.yotoplay.com/authorize")!
        let scopes = "user:content:manage user:content:view user:icons:manage" + (staySignedIn ? " offline_access" : "")
        url.queryItems = ["audience": "https://api.yotoplay.com", "scope": scopes, "response_type": "code", "client_id": clientID, "code_challenge": challenge, "code_challenge_method": "S256", "redirect_uri": "http://127.0.0.1:8787/callback", "state": state].map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    func login(clientID: String, staySignedIn: Bool = true) async throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw StudioError("Enter your Yoto developer client ID first.") }
        let verifier = UUID().uuidString + UUID().uuidString
        let state = UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let callback = "http://127.0.0.1:8787/callback"
        let authURL = try Self.authorizationURL(clientID: clientID, challenge: challenge, state: state, staySignedIn: staySignedIn)
        let attempt = UUID(); loginAttempt = attempt
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8787)
        let server = try NWListener(using: parameters)
        listener = server
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            loginContinuation = continuation
            server.stateUpdateHandler = { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    switch status {
                    case .ready:
                        if !NSWorkspace.shared.open(authURL) { self.finishLogin(.failure(StudioError("Could not open your browser."))) }
                    case .failed:
                        self.finishLogin(.failure(StudioError("Could not start sign-in. Port 8787 may already be in use.")))
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
                    Task { @MainActor in
                        guard let self else { connection.cancel(); return }
                        guard error == nil, let data, let text = String(data: data, encoding: .utf8),
                              let line = text.components(separatedBy: "\r\n").first else { connection.cancel(); return }
                        let parts = line.split(separator: " ")
                        guard parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/callback?"),
                              let received = URL(string: "http://127.0.0.1:8787" + parts[1]) else { connection.cancel(); return }
                        let query = URLComponents(url: received, resolvingAgainstBaseURL: false)?.queryItems ?? []
                        guard query.first(where: { $0.name == "state" })?.value == state else { connection.cancel(); return }
                        let body = "Return to Yoto Playlist Studio to finish signing in."
                        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                        self.finishLogin(.success(received))
                    }
                }
            }
            server.start(queue: .main)
            loginTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                if !Task.isCancelled { self?.finishLogin(.failure(StudioError("Sign-in timed out. Please try again."))) }
            }
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw StudioError("Sign-in verification failed. Please try again.") }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw StudioError("Yoto did not grant access. Check the developer app configuration.") }
        var request = URLRequest(url: URL(string: "https://login.yotoplay.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = ["grant_type": "authorization_code", "client_id": clientID, "code_verifier": verifier, "code": code, "redirect_uri": callback].map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let result = try await perform(request)
        guard loginAttempt == attempt, !Task.isCancelled else { throw CancellationError() }
        try authorization.accept(result, clientID: clientID, remember: staySignedIn)
    }
    private func perform(_ request: URLRequest) async throws -> JSON {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await (request.url?.host == "api.yotoplay.com" ? authorization.data(for: request) : session.data(for: request))
        guard let http = response as? HTTPURLResponse else { throw StudioError("Yoto did not respond.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw StudioError("Your Yoto session expired. Disconnect and sign in again.") }
            if http.statusCode == 403 { throw StudioError("Yoto denied access. Check your app permissions and playlist ownership.") }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
            let nested = object["error"] as? JSON ?? [:]
            let detail = nested["message"] as? String ?? object["message"] as? String ?? object["error_description"] as? String ?? object["error"] as? String ?? "No reason was supplied by Yoto."
            let safeDetail = String(detail.prefix(600)).replacingOccurrences(of: "Bearer \(token)", with: "[redacted]").replacingOccurrences(of: "https?://[^\\s]+", with: "[link omitted]", options: .regularExpression)
            let step: String
            switch request.url?.path {
            case "/media/transcode/audio/uploadUrl": step = "Preparing the audio upload"
            case "/content":
                let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? JSON }
                step = payload?["cardId"] == nil ? "Creating the playlist" : "Saving the playlist"
            default: step = "Yoto request"
            }
            throw StudioError("\(step) failed (HTTP \(http.statusCode)): \(safeDetail)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSON else { throw StudioError("Yoto returned an unexpected response.") }
        return object
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, type: String = "application/json") async throws -> JSON {
        guard connected else { throw StudioError("Connect your Yoto account first.") }
        var request = URLRequest(url: URL(string: "https://api.yotoplay.com" + path)!)
        request.httpMethod = method
        if method == "GET", path.hasPrefix("/content/") { request.cachePolicy = .reloadIgnoringLocalCacheData }
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }
    func playlists() async throws -> [Playlist] {
        let result = try await request("/content/mine")
        guard let cards = result["cards"] as? [JSON] else { throw StudioError("Yoto returned an unexpected playlist list.") }
        return cards.compactMap { card in
            guard let id = card["cardId"] as? String, card["deleted"] as? Bool != true else { return nil }
            return Playlist(id: id, title: card["title"] as? String ?? "Untitled playlist")
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func card(_ id: String) async throws -> JSON {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let result = try await request("/content/\(safe)")
        guard let card = result["card"] as? JSON else { throw StudioError("Yoto returned an unexpected playlist.") }
        return card
    }
    func iconURL(cardID: String, reference: String) async throws -> URL {
        let mediaID: String
        if reference.hasPrefix("yoto:#") { mediaID = String(reference.dropFirst(6)) }
        else if reference.hasPrefix("yoto:") { mediaID = String(reference.dropFirst(5)) }
        else { throw StudioError("Unrecognized icon reference.") }
        guard !mediaID.isEmpty else { throw StudioError("Missing icon ID.") }
        let safeCard = cardID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let safeMedia = mediaID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let result = try await request("/card/\(safeCard)/media/\(safeMedia)")
        let media = result["media"] as? JSON ?? [:]
        guard let address = media["url"] as? String, let url = URL(string: address), url.scheme == "https", url.host != nil else {
            throw StudioError("Yoto returned no image URL for this icon.")
        }
        return url
    }
    func icons(owned: Bool = false) async throws -> [LibraryIcon] {
        let result = try await request(owned ? "/media/displayIcons/user/me" : "/media/displayIcons/user/yoto")
        guard let icons = result["displayIcons"] as? [JSON] else { throw StudioError("Yoto returned an unexpected icon library.") }
        return icons.compactMap { icon in
            guard let id = icon["mediaId"] as? String else { return nil }
            return LibraryIcon(id: id, title: icon["title"] as? String ?? "Yoto icon", tags: icon["publicTags"] as? [String] ?? [], url: (icon["url"] as? String).flatMap(URL.init(string:)))
        }
    }
    func upload(_ pixels: [UInt32]) async throws -> String {
        let data = try PixelArt.png(pixels)
        let result = try await request("/media/displayIcons/user/me/upload?autoConvert=false&filename=playlist-studio", method: "POST", body: data, type: "image/png")
        guard let icon = result["displayIcon"] as? JSON, let id = icon["mediaId"] as? String else { throw StudioError("Yoto did not return an uploaded icon ID.") }
        return "yoto:#" + id
    }
    static func processingFailure(_ transcode: JSON) -> String? {
        // Error fields can coexist with null result fields in an HTTP 202 body.
        if let error = transcode["error"] as? String, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(error.prefix(600)) }
        if let error = transcode["error"] as? JSON {
            for key in ["message", "description", "code"] {
                if let text = error[key] as? String, !text.isEmpty { return String(text.prefix(600)) }
            }
            if !error.isEmpty { return "Yoto reported an audio conversion error." }
        }
        if let error = transcode["error"] as? Bool, error { return "Yoto reported an audio conversion error." }
        if transcode["status"] as? String == "failed" || transcode["status"] as? String == "error" { return "Yoto reported an audio conversion error." }
        return nil
    }
    func uploadAudio(_ file: URL, progress: @escaping (String) -> Void) async throws -> JSON {
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Upload and process audio for Yoto")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        progress("Requesting a Yoto upload…")
        let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
        let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "sha256", value: checksum), URLQueryItem(name: "filename", value: file.lastPathComponent)]
        let response = try await request("/media/transcode/audio/uploadUrl?" + (query.percentEncodedQuery ?? ""))
        guard let upload = response["upload"] as? JSON, let id = upload["uploadId"] as? String else { throw StudioError("Yoto returned no audio upload ID.") }
        if let address = upload["uploadUrl"] as? String {
            guard let url = URL(string: address), url.scheme == "https" else { throw StudioError("Yoto returned an invalid audio upload URL.") }
            var put = URLRequest(url: url)
            put.httpMethod = "PUT"; put.timeoutInterval = 300
            put.setValue("audio/mpeg", forHTTPHeaderField: "Content-Type")
            // The signed storage URL carries its own authorization. Never forward the Yoto token.
            progress("Uploading MP3 to Yoto…")
            let (_, uploaded) = try await session.upload(for: put, fromFile: file)
            guard let http = uploaded as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw StudioError("Sending the MP3 to Yoto failed (HTTP \((uploaded as? HTTPURLResponse)?.statusCode ?? 0)). The playlist has not changed.") }
        }
        progress("Waiting for Yoto to process the audio…")
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let deadline = Date().addingTimeInterval(180)
        for attempt in 0..<90 {
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            progress("Waiting for Yoto audio processing (check \(attempt + 1))…")
            var poll = URLRequest(url: URL(string: "https://api.yotoplay.com/media/upload/\(safeID)/transcoded?loudnorm=false")!)
            poll.timeoutInterval = 30
            let (data, response) = try await authorization.data(for: poll)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
            let transcodeFields = object["transcode"] as? JSON ?? [:]
            var diagnostic: JSON = ["httpStatus": code, "responseFields": object.keys.sorted(), "transcodeFields": transcodeFields.keys.sorted(), "check": attempt + 1]
            if let error = object["error"] as? JSON { diagnostic["errorCode"] = error["code"]; diagnostic["errorMessage"] = error["message"] }
            if let state = transcodeFields["status"] as? String { diagnostic["status"] = state }
            if let reason = Self.processingFailure(transcodeFields) { diagnostic["processingError"] = reason }
            if let info = transcodeFields["transcodedInfo"] as? JSON { diagnostic["mediaFields"] = info.keys.sorted() }
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("yoto-studio-processing-" + safeID + ".json"), options: .atomic) }
            if code == 401 { throw StudioError("Your Yoto sign-in expired. Sign in again before uploading.") }
            if code == 403 { throw StudioError("Yoto denied audio access. Check user:content:manage in the developer app.") }
            if (200..<300).contains(code), let reason = Self.processingFailure(transcodeFields) {
                throw StudioError("Yoto could not process the audio: " + reason + ". Your local MP3 is kept. For long recordings, try shorter tracks.")
            }
            if (200..<300).contains(code), let object = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
               let transcode = object["transcode"] as? JSON, let hash = transcode["transcodedSha256"] as? String, !hash.isEmpty { return transcode }
            guard (200..<300).contains(code) || code == 404 else { throw StudioError("Yoto audio processing failed (HTTP \(code)). The playlist has not changed.") }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw StudioError("Yoto audio processing timed out. No track was appended; you can retry.")
    }
    func saveOrder(_ order: [String], baseline: JSON, backup: (JSON) throws -> Void = { _ in }) async throws -> JSON {
        guard let id = baseline["cardId"] as? String else { throw StudioError("Choose a saved playlist first.") }
        let latest = try await card(id)
        guard try PlaylistOrder.sameContent(latest, baseline) else {
            throw StudioError("This playlist’s tracks or artwork changed. Your order is still staged. Choose Reload latest order to start from the current playlist.")
        }
        let payload = try PlaylistOrder.payload(latest, order: order)
        try backup(latest)
        return try await save(payload)
    }
    func appendAudioBatch(_ tracks: [(transcode: JSON, title: String)], artwork: [Int: String] = [:], to id: String, backup: (JSON) throws -> Void = { _ in }) async throws -> JSON {
        // Appending does not depend on the view's old snapshot. Build from the
        // server's current content so successive batches and background edits survive.
        let latest = try await card(id)
        guard artwork.keys.allSatisfy({ tracks.indices.contains($0) }) else { throw StudioError("The artwork selection does not match this audio batch.") }
        var payload = try AudioImport.appendBatch(tracks, to: latest)
        let start = ((latest["content"] as? JSON)?["chapters"] as? [JSON] ?? []).count
        let references = Dictionary(uniqueKeysWithValues: artwork.map { ("\(start + $0.key):0", $0.value) })
        if !references.isEmpty { payload = try CardEditor.applying(references, to: payload) }
        try backup(latest)
        return try await save(payload)
    }
    func createPlaylist(_ payload: JSON) async throws -> JSON {
        guard payload["cardId"] == nil, let content = payload["content"] as? JSON,
              let chapters = content["chapters"] as? [JSON], !chapters.isEmpty else {
            throw StudioError("Add at least one audio track before creating the playlist.")
        }
        let response = try await request("/content", method: "POST", body: JSONSerialization.data(withJSONObject: payload))
        let card = response["card"] as? JSON ?? response
        guard let id = card["cardId"] as? String, !id.isEmpty else {
            throw StudioError("Yoto may have created the playlist but returned no playlist ID. Refresh your library before trying again.")
        }
        return card
    }
    @discardableResult
    func save(_ payload: JSON) async throws -> JSON {
        let response = try await request("/content", method: "POST", body: JSONSerialization.data(withJSONObject: payload))
        return response["card"] as? JSON ?? payload
    }
}
