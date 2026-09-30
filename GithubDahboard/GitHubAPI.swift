import Foundation
import SwiftUI
import OSLog

struct GitHubUser: Codable, Identifiable {
    let id: Int
    let login: String
    let name: String?
    let avatar_url: URL?
    let bio: String?
    let followers: Int?
    let public_repos: Int?
}

@MainActor
@Observable
final class GitHubViewModel {
    var token: String = ""
    var user: GitHubUser?
    var aTraiter: ATraiterData?
    var aTraiterWarning: String?
    var isLoading: Bool = false
    var errorMessage: String?
    
    init() {
        if let saved = try? KeychainStorage.loadToken() {
            self.token = saved
        }
    }

    func loadAuthenticatedUser() async {
        errorMessage = nil
        aTraiterWarning = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try? KeychainStorage.saveToken(token)
            let user = try await GitHubAPI(token: token).fetchAuthenticatedUser()
            self.user = user
            let result = try await GitHubAPI(token: token).fetchATraiter(login: user.login)
            self.aTraiter = result.data
            self.aTraiterWarning = result.warning
        } catch {
            self.errorMessage = (error as? GitHubAPI.APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
    
    func logout() {
        user = nil
        aTraiter = nil
        aTraiterWarning = nil
        errorMessage = nil
        token = ""
        try? KeychainStorage.deleteToken()
    }
}

struct GitHubAPI {
    private static let logger = Logger(subsystem: "com.githubdashboard.app", category: "network")

    enum APIError: LocalizedError {
        case missingToken
        case badStatus(Int)
        case decoding(Error)
        case graphQL(String)

        var errorDescription: String? {
            switch self {
            case .missingToken: return "Token manquant."
            case .badStatus(let code): return "Réponse invalide du serveur (\(code))."
            case .decoding(let err): return "Erreur de décodage: \(err.localizedDescription)"
            case .graphQL(let message): return message
            }
        }
    }

    let token: String

    private var baseURL: URL { URL(string: "https://api.github.com")! }

    private func request(path: String, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingToken }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        var req = URLRequest(url: components.url!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        GitHubAPI.logger.info("➡️ Request: \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "nil")")
        if let headers = req.allHTTPHeaderFields {
            GitHubAPI.logger.debug("Headers: \(String(describing: headers.redactingSensitiveValues()))")
        }
        return req
    }
    
    private func dataWithRetry(for request: URLRequest, retries: Int = 2) async throws -> (Data, URLResponse) {
        var attempt = 0
        var lastError: Error?
        while attempt <= retries {
            do {
                return try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                // Backoff: 0.5s, 1.0s, 2.0s
                let delay = pow(2.0, Double(attempt)) * 0.5
                GitHubAPI.logger.error("Network error attempt \(attempt): \(String(describing: error)) — retrying in \(delay, format: .fixed(precision: 1))s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    func fetchAuthenticatedUser() async throws -> GitHubUser {
        var req = try request(path: "/user")
        req.httpMethod = "GET"
        let (data, resp) = try await dataWithRetry(for: req)
        GitHubAPI.logger.info("⬅️ /user response received")
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            GitHubAPI.logger.error("/user bad status: \(http.statusCode)")
            throw APIError.badStatus(http.statusCode)
        }
        do { return try JSONDecoder().decode(GitHubUser.self, from: data) }
        catch {
            GitHubAPI.logger.error("Decoding /user failed: \(String(describing: error))")
            throw APIError.decoding(error)
        }
    }

    func fetchATraiter(login: String) async throws -> (data: ATraiterData, warning: String?) {
        let organizations = try await fetchOrganizations()
        var req = try request(path: "/graphql")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ATraiterRequest(
            query: ATraiterQuery.document,
            variables: ATraiterQuery.variables(for: login, organizations: organizations)
        ))
        let (data, resp) = try await dataWithRetry(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode)
        }
        do {
            let response = try JSONDecoder().decode(ATraiterResponse.self, from: data)
            guard let result = response.data else {
                throw APIError.graphQL(response.errors?.first?.message ?? "Réponse GraphQL vide.")
            }
            return (result, response.errors?.first?.message)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func fetchOrganizations() async throws -> [String] {
        var req = try request(path: "/graphql")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ATraiterRequest(
            query: ATraiterQuery.organizationsDocument,
            variables: [:]
        ))
        let (data, resp) = try await dataWithRetry(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(ATraiterOrganizationsResponse.self, from: data)
                .data?.viewer.organizations.nodes.map(\.login) ?? []
        } catch {
            throw APIError.decoding(error)
        }
    }
}

private extension [String: String] {
    func redactingSensitiveValues() -> [String: String] {
        mapValues { value in
            if value.hasPrefix("token ") {
                let components = value.split(separator: " ", maxSplits: 1)
                if let secret = components.last {
                    return "\(components[0]) \(secret.prefix(6))…\(String(repeating: "•", count: 4))"
                }
            }
            return value
        }
    }
}
