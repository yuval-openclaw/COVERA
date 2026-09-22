import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case http(status: Int, message: String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "You’re signed out. Sign in to continue.")
        case let .http(_, message):
            return message
        case .transport:
            return String(localized: "Could not reach Covera. Check your connection and try again.")
        case .decoding:
            // Never paper over a shape mismatch: a response we cannot fully
            // decode may be a plan whose citations we would drop on the floor.
            return String(localized: "Covera received a reply it could not read safely, so nothing is shown.")
        }
    }
}

/// Talks to the Covera API.
///
/// Deliberately thin. No caching of plans and no local persistence of policy
/// figures: every screen re-asks the server, which re-reads the documents. A
/// cached number is a number nobody re-verified.
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = APIClient.defaultBaseURL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter.coveraFractional.date(from: text) { return date }
            if let date = ISO8601DateFormatter.coveraPlain.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised timestamp \(text)"
            )
        }
        self.decoder = decoder
    }

    static var defaultBaseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "CoveraAPIBaseURL") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    // MARK: - Requests

    func documents() async throws -> [PolicyDocument] {
        try await send(path: "/documents", method: "GET", body: nil, as: DocumentListResponse.self).documents
    }

    func guidance(situation: String, answers: [String: String] = [:]) async throws -> GuidanceResponse {
        var payload: [String: Any] = ["situation": situation, "locale": Self.locale]
        if !answers.isEmpty { payload["answers"] = answers }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await send(path: "/guidance", method: "POST", body: body, as: GuidanceResponse.self)
    }

    func upload(fileURL: URL, filename: String) async throws -> UploadResponse {
        let boundary = "covera.\(UUID().uuidString)"
        var body = Data()
        let data = try Data(contentsOf: fileURL)

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/pdf\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        return try await send(
            path: "/documents",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            as: UploadResponse.self
        )
    }

    /// The original uploaded file, decrypted by the server on the way out.
    func documentFile(id: String) async throws -> Data {
        try await raw(path: "/documents/\(id)/file", method: "GET", body: nil).0
    }

    func chat(history: [(role: String, content: String)]) async throws -> ChatReply {
        let payload: [String: Any] = [
            "messages": history.map { ["role": $0.role, "content": $0.content] },
            "locale": Self.locale,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await send(path: "/chat", method: "POST", body: body, as: ChatReply.self)
    }

    /// The reader's language, so the server writes plans and answers in it.
    static var locale: String { AppLanguage.current.rawValue }

    // MARK: - Authentication

    struct AuthResponse: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let id: String
            let email: String
        }
        let token: String
        let user: User
    }

    private struct MeResponse: Decodable {
        struct User: Decodable { let email: String }
        let user: User
    }

    func signIn(email: String, password: String, createAccount: Bool) async throws -> AuthResponse {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try await send(
            path: createAccount ? "/auth/register" : "/auth/login",
            method: "POST", body: body, as: AuthResponse.self, authenticated: false
        )
    }

    func signInAsGuest() async throws -> AuthResponse {
        try await send(path: "/auth/guest", method: "POST", body: nil, as: AuthResponse.self, authenticated: false)
    }

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        let body = try JSONSerialization.data(withJSONObject: ["idToken": idToken])
        return try await send(path: "/auth/google", method: "POST", body: body, as: AuthResponse.self, authenticated: false)
    }

    /// Ends the session on the server. Best effort: signing out locally must
    /// work even offline.
    func signOut() async {
        _ = try? await raw(path: "/auth/logout", method: "POST", body: nil)
    }

    func currentEmail() async throws -> String {
        try await send(path: "/auth/me", method: "GET", body: nil, as: MeResponse.self).user.email
    }

    func exportAccount() async throws -> Data {
        try await raw(path: "/account/export", method: "GET", body: nil).0
    }

    /// Records on the server that this account consented to the processing of
    /// health information under the given version of the privacy policy.
    func recordConsent(version: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["version": version])
        _ = try await raw(path: "/account/consent", method: "POST", body: body)
    }

    func deleteAccount() async throws {
        _ = try await raw(path: "/account", method: "DELETE", body: nil)
    }

    // MARK: - Plumbing

    private func send<T: Decodable>(
        path: String,
        method: String,
        body: Data?,
        contentType: String = "application/json",
        as type: T.Type,
        authenticated: Bool = true
    ) async throws -> T {
        let (data, _) = try await raw(
            path: path, method: method, body: body, contentType: contentType, authenticated: authenticated
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func raw(
        path: String,
        method: String,
        body: Data?,
        contentType: String = "application/json",
        authenticated: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let token = await Session.shared.token
        if authenticated && token == nil { throw APIError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 90 // Extraction and guidance both call a model.
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            if authenticated && http.statusCode == 401 {
                // The session is gone server-side — expired, signed out
                // elsewhere, or the account deleted. Every later request would
                // fail too, so return to the sign-in screen now.
                await Session.shared.signOut()
                await MainActor.run { AuthState.shared.didSignOut() }
            }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            // Route handlers send `error`; errors thrown inside Fastify send a
            // generic `error` label with the real text in `message`.
            let message = (object?["message"] as? String) ?? (object?["error"] as? String)
            throw APIError.http(
                status: http.statusCode,
                message: message ?? String(localized: "Covera could not complete that request.")
            )
        }
        return (data, http)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}

// ISO8601DateFormatter is documented as thread-safe but is not marked Sendable,
// so the compiler cannot know that; `nonisolated(unsafe)` records the decision.
private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let coveraFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let coveraPlain = ISO8601DateFormatter()
}
