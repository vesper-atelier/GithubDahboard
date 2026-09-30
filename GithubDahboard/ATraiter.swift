import Foundation

struct ATraiterResponse: Codable {
    let data: ATraiterData?
    let errors: [ATraiterGraphQLError]?
}

struct ATraiterOrganizationsResponse: Codable {
    let data: ATraiterOrganizationsData?
}

struct ATraiterOrganizationsData: Codable {
    let viewer: ATraiterViewer
}

struct ATraiterViewer: Codable {
    let organizations: ATraiterOrganizations
}

struct ATraiterOrganizations: Codable {
    let nodes: [ATraiterOrganization]
}

struct ATraiterOrganization: Codable {
    let login: String
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
    let derive: ATraiterSearch?

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

    var driftIssues: [ATraiterIssue] {
        (derive?.nodes ?? []).compactMap(ATraiterIssue.init).sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct ATraiterPullRequestGroup: Identifiable {
    let repository: String
    let pullRequests: [ATraiterPullRequest]

    var id: String { repository }

    var dependencyPullRequests: [ATraiterPullRequest] {
        pullRequests.filter { $0.isDependencyUpdate }
    }

    var otherPullRequests: [ATraiterPullRequest] {
        pullRequests.filter { !$0.isDependencyUpdate }
    }

    var dependencyCIState: String? {
        let states = dependencyPullRequests.compactMap(\.ciState)
        if states.contains(where: { ["FAILURE", "ERROR"].contains($0) }) { return "FAILURE" }
        if states.contains(where: { ["PENDING", "EXPECTED"].contains($0) }) { return "PENDING" }
        if states.contains("SUCCESS") { return "SUCCESS" }
        return nil
    }
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
    let author: ATraiterAuthor?
    let comments: ATraiterComments?
    let timelineItems: ATraiterTimeline?
}

struct ATraiterAuthor: Codable {
    let login: String?
}

struct ATraiterRepository: Codable {
    let nameWithOwner: String?
}

struct ATraiterCommits: Codable {
    let nodes: [ATraiterCommitNode?]?
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

struct ATraiterComments: Codable {
    let nodes: [ATraiterComment?]?
}

struct ATraiterComment: Codable {
    let author: ATraiterAuthor?
    let body: String?
    let createdAt: String?
}

struct ATraiterTimeline: Codable {
    let nodes: [ATraiterTimelineNode?]?
}

struct ATraiterTimelineNode: Codable {
    let source: ATraiterReferencedPullRequest?
}

struct ATraiterReferencedPullRequest: Codable {
    let number: Int?
    let url: URL?
    let isDraft: Bool?
    let state: String?
    let commits: ATraiterCommits?
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
    let authorLogin: String?

    var id: String { "\(repository)#\(number)" }

    var isDependencyUpdate: Bool {
        guard let authorLogin else { return false }
        let author = authorLogin.lowercased()
        return author.hasPrefix("dependabot") || author.hasPrefix("renovate")
    }

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
        self.ciState = node.commits?.nodes?.first??.commit?.statusCheckRollup?.state
        self.authorLogin = node.author?.login
    }
}

struct ATraiterIssue: Identifiable {
    static let agentLogin = "echo-scribe"

    let number: Int
    let title: String
    let url: URL
    let repository: String
    let updatedAt: String
    let agentStatus: AgentStatus?
    private let reportPosted: Bool

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
        let comments = node.comments?.nodes?.compactMap { $0 } ?? []
        let references = node.timelineItems?.nodes?.compactMap { $0?.source }.filter { $0.number != nil } ?? []
        self.reportPosted = comments.contains {
            $0.author?.login == Self.agentLogin && ($0.body?.hasPrefix("Conforme") ?? false)
        }
        if node.comments == nil && node.timelineItems == nil {
            self.agentStatus = nil
        } else if let pullRequest = references.max(by: { ($0.number ?? 0) < ($1.number ?? 0) }),
                  pullRequest.state == "MERGED",
                  let number = pullRequest.number,
                  let url = pullRequest.url {
            self.agentStatus = .merged(number: number, url: url)
        } else if let pullRequest = references.max(by: { ($0.number ?? 0) < ($1.number ?? 0) }),
                  pullRequest.state == "OPEN",
                  let number = pullRequest.number,
                  let url = pullRequest.url {
            self.agentStatus = .pullRequest(
                number: number,
                url: url,
                isDraft: pullRequest.isDraft ?? false,
                ciState: pullRequest.commits?.nodes?.first??.commit?.statusCheckRollup?.state
            )
        } else if comments.contains(where: { $0.author?.login == Self.agentLogin && ($0.body?.hasPrefix("Conforme") ?? false) }) {
            self.agentStatus = .reportPosted
        } else if comments.contains(where: { $0.author?.login == Self.agentLogin && ($0.body?.hasPrefix("Pris en charge") ?? false) }) {
            self.agentStatus = .inProgress
        } else {
            self.agentStatus = .toDo
        }
    }

    var hasReport: Bool {
        reportPosted
    }
}

enum AgentStatus: Equatable {
    case toDo
    case inProgress
    case pullRequest(number: Int, url: URL, isDraft: Bool, ciState: String?)
    case merged(number: Int, url: URL)
    case reportPosted
}

enum ATraiterQuery {
    static let organizationsDocument = "query { viewer { organizations(first: 100) { nodes { login } } } }"

    static let document = """
    query ATraiter($prs: String!, $bus: String!, $mine: String!, $derive: String!) {
      prs: search(query: $prs, type: ISSUE, first: 50) {
        nodes {
          ... on PullRequest {
             number title url isDraft updatedAt reviewDecision
             author { login }
            repository { nameWithOwner }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
      bus: search(query: $bus, type: ISSUE, first: 50) {
        nodes {
          ... on Issue {
            number title url updatedAt repository { nameWithOwner }
            comments(last: 20) { nodes { author { login } body createdAt } }
            timelineItems(itemTypes: [CROSS_REFERENCED_EVENT], last: 10) {
              nodes {
                ... on CrossReferencedEvent {
                  source {
                    ... on PullRequest {
                      number url isDraft state
                      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                    }
                  }
                }
              }
            }
          }
        }
      }
      mine: search(query: $mine, type: ISSUE, first: 50) {
        nodes { ... on Issue { number title url updatedAt repository { nameWithOwner } } }
      }
      derive: search(query: $derive, type: ISSUE, first: 20) {
        nodes { ... on Issue { number title url updatedAt repository { nameWithOwner } } }
      }
    }
    """

    static func variables(for login: String, organizations: [String]) -> [String: String] {
        let orgs = Set(organizations + ["nhipster-com", "vesper-atelier"]).sorted()
        return [
            "prs": "is:open is:pr archived:false user:\(login) \(orgs.map { "org:\($0)" }.joined(separator: " "))",
            "bus": "is:open is:issue repo:vesper-atelier/taches label:pour:echo-scribe",
            "mine": "is:open is:issue archived:false assignee:\(login)"
            , "derive": "is:open is:issue repo:nhipster-com/platform-homelab label:derive-infra"
        ]
    }
}
