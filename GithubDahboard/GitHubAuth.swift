import Foundation

struct GitHubSession: Codable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
}

enum GitHubAuth {
    static let clientID = "A_RENSEIGNER"
    static let sessionAccount = "github_session"
    static var isConfigured: Bool { clientID != "A_RENSEIGNER" }

    struct DeviceAuthorization {
        let deviceCode: String
        let userCode: String
        let verificationURI: URL
        let expiresIn: Int
        let interval: Int
    }

    enum AuthError: LocalizedError {
        case expired
        case denied
        case server(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .expired: return "Code expiré, recommencez."
            case .denied: return "Connexion refusée sur GitHub."
            case .server(let message): return message
            case .invalidResponse: return "Réponse invalide de GitHub."
            }
        }
    }

    private struct DeviceResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationURI: URL
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code", userCode = "user_code"
            case verificationURI = "verification_uri", expiresIn = "expires_in", interval
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let refreshTokenExpiresIn: Int?
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token"
            case expiresIn = "expires_in", refreshTokenExpiresIn = "refresh_token_expires_in"
            case error, errorDescription = "error_description"
        }
    }

    static func authorize(onCode: @escaping @MainActor (String, URL) -> Void) async throws -> GitHubSession {
        let request = try formRequest(path: "/login/device/code", body: ["client_id": clientID])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let device = try JSONDecoder().decode(DeviceResponse.self, from: data)
        await onCode(device.userCode, device.verificationURI)

        var interval = max(device.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let tokenRequest = try formRequest(path: "/login/oauth/access_token", body: [
                "client_id": clientID,
                "device_code": device.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
            try validate(tokenResponse)
            let token = try JSONDecoder().decode(TokenResponse.self, from: tokenData)
            if let error = token.error {
                switch error {
                case "authorization_pending": continue
                case "slow_down": interval += 5
                case "expired_token": throw AuthError.expired
                case "access_denied": throw AuthError.denied
                default: throw AuthError.server(token.errorDescription ?? error)
                }
                continue
            }
            guard let access = token.accessToken, let refresh = token.refreshToken,
                  let accessLifetime = token.expiresIn, let refreshLifetime = token.refreshTokenExpiresIn else {
                throw AuthError.invalidResponse
            }
            return GitHubSession(accessToken: access, refreshToken: refresh,
                                 accessExpiresAt: Date().addingTimeInterval(TimeInterval(accessLifetime)),
                                 refreshExpiresAt: Date().addingTimeInterval(TimeInterval(refreshLifetime)))
        }
        throw AuthError.expired
    }

    static func refresh(_ session: GitHubSession) async throws -> GitHubSession {
        guard session.refreshExpiresAt > Date() else { throw AuthError.server("Session expirée, reconnectez-vous.") }
        let request = try formRequest(path: "/login/oauth/access_token", body: [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": session.refreshToken
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let access = token.accessToken, let refresh = token.refreshToken,
              let accessLifetime = token.expiresIn, let refreshLifetime = token.refreshTokenExpiresIn else {
            throw AuthError.server(token.errorDescription ?? token.error ?? "Rafraîchissement impossible.")
        }
        return GitHubSession(accessToken: access, refreshToken: refresh,
                             accessExpiresAt: Date().addingTimeInterval(TimeInterval(accessLifetime)),
                             refreshExpiresAt: Date().addingTimeInterval(TimeInterval(refreshLifetime)))
    }

    private static func formRequest(path: String, body: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://github.com\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }
    }
}
