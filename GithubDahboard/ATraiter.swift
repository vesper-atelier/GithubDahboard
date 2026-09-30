import Foundation

struct ATraiterResponse: Codable {
    let data: ATraiterData?
    let errors: [ATraiterGraphQLError]?
}

struct ATraiterRequest: Codable {
    let query: String
    let variables: [String: String]
}

struct ATraiterGraphQLError: Codable {
    let message: String
}

struct ATraiterData: Codable {
    let prs: ATraiterSearch?
    let bus: ATraiterSearch?
    let mine: ATraiterSearch?

    var pullRequestsByRepository: [ATraiterPullRequestGroup] {
        let pullRequests = (prs?.nodes ?? []).compactMap(ATraiterPullRequest.init)
        let grouped = Dictionary(grouping: pullRequests) { $0.repository }
        return grouped.keys.sorted().map { repository in
            ATraiterPullRequestGroup(
                repository: repository,
                pullRequests: grouped[repository, default: []].sorted { $0.updatedAt > $1.updatedAt }
            )
        }
    }

    var busIssues: [ATraiterIssue] {
        (bus?.nodes ?? []).compactMap(ATraiterIssue.init).sorted { $0.updatedAt > $1.updatedAt }
    }

    var assignedIssues: [ATraiterIssue] {
        (mine?.nodes ?? []).compactMap(ATraiterIssue.init).sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct ATraiterPullRequestGroup: Identifiable {
    let repository: String
    let pullRequests: [ATraiterPullRequest]

    var id: String { repository }
}

struct ATraiterSearch: Codable {
    let nodes: [ATraiterNode]?
}

struct ATraiterNode: Codable {
    let number: Int?
    let title: String?
    let url: URL?
    let isDraft: Bool?
    let updatedAt: String?
    let reviewDecision: String?
    let repository: ATraiterRepository?
    let commits: ATraiterCommits?
}

struct ATraiterRepository: Codable {
    let nameWithOwner: String?
}

struct ATraiterCommits: Codable {
    let nodes: [ATraiterCommitNode]?
}

struct ATraiterCommitNode: Codable {
    let commit: ATraiterCommit?
}

struct ATraiterCommit: Codable {
    let statusCheckRollup: ATraiterStatusCheckRollup?
}

struct ATraiterStatusCheckRollup: Codable {
    let state: String?
}

struct ATraiterPullRequest: Identifiable {
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let updatedAt: String
    let isDraft: Bool
    let reviewDecision: String?
    let ciState: String?

    var id: String { "\(repository)#\(number)" }

    init?(node: ATraiterNode) {
        guard let number = node.number,
              let title = node.title,
              let url = node.url,
              let repository = node.repository?.nameWithOwner else { return nil }
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.updatedAt = node.updatedAt ?? ""
        self.isDraft = node.isDraft ?? false
        self.reviewDecision = node.reviewDecision
        self.ciState = node.commits?.nodes?.first?.commit?.statusCheckRollup?.state
    }
}

struct ATraiterIssue: Identifiable {
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let updatedAt: String

    var id: String { "\(repository)#\(number)" }

    init?(node: ATraiterNode) {
        guard let number = node.number,
              let title = node.title,
              let url = node.url,
              let repository = node.repository?.nameWithOwner else { return nil }
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.updatedAt = node.updatedAt ?? ""
    }
}

enum ATraiterQuery {
    static let document = """
    query ATraiter($prs: String!, $bus: String!, $mine: String!) {
      prs: search(query: $prs, type: ISSUE, first: 50) {
        nodes {
          ... on PullRequest {
            number title url isDraft updatedAt reviewDecision
            repository { nameWithOwner }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
      bus: search(query: $bus, type: ISSUE, first: 50) {
        nodes { ... on Issue { number title url updatedAt repository { nameWithOwner } } }
      }
      mine: search(query: $mine, type: ISSUE, first: 50) {
        nodes { ... on Issue { number title url updatedAt repository { nameWithOwner } } }
      }
    }
    """

    static func variables(for login: String) -> [String: String] {
        [
            "prs": "is:open is:pr archived:false user:\(login) org:nhipster-com org:vesper-atelier",
            "bus": "is:open is:issue repo:vesper-atelier/taches label:pour:echo-scribe",
            "mine": "is:open is:issue archived:false assignee:\(login)"
        ]
    }
}
