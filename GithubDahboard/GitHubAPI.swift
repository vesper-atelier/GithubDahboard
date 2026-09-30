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

struct GitHubRepo: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let stargazers_count: Int
    let language: String?
    let html_url: URL
}

@MainActor
@Observable
final class GitHubViewModel {
    var token: String = ""
    var user: GitHubUser?
    var repos: [GitHubRepo] = []
    var aTraiter: ATraiterData?
    var isLoading: Bool = false
    var errorMessage: String?
    
    init() {
        if let saved = try? KeychainStorage.loadToken() {
            self.token = saved
        }
    }

    func loadAuthenticatedUser() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try? KeychainStorage.saveToken(token)
            let user = try await GitHubAPI(token: token).fetchAuthenticatedUser()
            self.user = user
            self.aTraiter = try await GitHubAPI(token: token).fetchATraiter(login: user.login)
        } catch {
            self.errorMessage = (error as? GitHubAPI.APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
    
    func logout() {
        user = nil
        repos = []
        aTraiter = nil
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

    func fetchUserRepos(login: String) async throws -> [GitHubRepo] {
        var req = try request(path: "/users/\(login)/repos", queryItems: [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "20")
        ])
        req.httpMethod = "GET"
        let (data, resp) = try await dataWithRetry(for: req)
        GitHubAPI.logger.info("⬅️ /users/\(login)/repos response received")
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            GitHubAPI.logger.error("/users/\(login)/repos bad status: \(http.statusCode)")
            throw APIError.badStatus(http.statusCode)
        }
        do { return try JSONDecoder().decode([GitHubRepo].self, from: data) }
        catch {
            GitHubAPI.logger.error("Decoding repos failed: \(String(describing: error))")
            throw APIError.decoding(error)
        }
    }

    func fetchATraiter(login: String) async throws -> ATraiterData {
        var req = try request(path: "/graphql")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ATraiterRequest(
            query: ATraiterQuery.document,
            variables: ATraiterQuery.variables(for: login)
        ))
        let (data, resp) = try await dataWithRetry(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode)
        }
        do {
            let response = try JSONDecoder().decode(ATraiterResponse.self, from: data)
            if let message = response.errors?.first?.message {
                throw APIError.graphQL(message)
            }
            guard let result = response.data else {
                throw APIError.graphQL("Réponse GraphQL vide.")
            }
            return result
        } catch let error as APIError {
            throw error
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
