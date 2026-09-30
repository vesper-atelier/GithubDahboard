import SwiftUI

struct ATraiterView: View {
    let data: ATraiterData?
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let warning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            if let driftIssues = data?.driftIssues, !driftIssues.isEmpty {
                issuesSection(title: "Dérive de l'infra", issues: driftIssues, icon: "exclamationmark.triangle.fill")
            }
            pullRequestsSection
            issuesSection(title: "Bus echo-scribe", issues: data?.busIssues ?? [], showsAgentStatus: true)
            issuesSection(title: "Assignées à moi", issues: data?.assignedIssues ?? [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pullRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PR ouvertes")
                .font(.headline)
            if let groups = data?.pullRequestsByRepository, !groups.isEmpty {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.repository)
                            .font(.subheadline)
                            .bold()
                        ForEach(group.otherPullRequests) { pullRequest in
                            pullRequestRow(pullRequest)
                        }
                        if !group.dependencyPullRequests.isEmpty {
                            DisclosureGroup {
                                ForEach(group.dependencyPullRequests) { pullRequest in
                                    pullRequestRow(pullRequest)
                                }
                            } label: {
                                HStack {
                                    ciLabel(for: group.dependencyCIState)
                                    Text("\(group.dependencyPullRequests.count) mises à jour de dépendances")
                                }
                            }
                        }
                    }
                }
            } else {
                emptyMessage
            }
        }
    }

    @ViewBuilder
    private func pullRequestRow(_ pullRequest: ATraiterPullRequest) -> some View {
        Link(destination: pullRequest.url) {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(pullRequest.number) \(pullRequest.title)")
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    ciLabel(for: pullRequest.ciState)
                    reviewLabel(for: pullRequest.reviewDecision)
                    if pullRequest.isDraft {
                        Text("Brouillon")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .padding(.vertical, 6)
        }
        Divider()
    }

    @ViewBuilder
    private func issuesSection(title: String, issues: [ATraiterIssue], icon: String? = nil, showsAgentStatus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).foregroundStyle(.red)
                }
                Text(title).font(.headline)
            }
            if issues.isEmpty {
                emptyMessage
            } else {
                ForEach(issues) { issue in
                    if showsAgentStatus {
                        VStack(alignment: .leading, spacing: 3) {
                            Link(destination: issue.url) {
                                Text("#\(issue.number) \(issue.title)")
                                    .foregroundStyle(.primary)
                            }
                            agentStatusRow(for: issue)
                            Text(issue.repository)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        Link(destination: issue.url) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("#\(issue.number) \(issue.title)")
                                    .foregroundStyle(.primary)
                                Text(issue.repository)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private var emptyMessage: some View {
        Text("Rien à traiter")
            .foregroundStyle(.secondary)
    }

    private func ciLabel(for state: String?) -> some View {
        let icon: String
        let color: Color
        switch state {
        case "SUCCESS": (icon, color) = ("checkmark.circle.fill", .green)
        case "FAILURE", "ERROR": (icon, color) = ("xmark.circle.fill", .red)
        case "PENDING", "EXPECTED": (icon, color) = ("clock", .orange)
        default: (icon, color) = ("minus.circle", .gray)
        }
        return Image(systemName: icon)
            .foregroundStyle(color)
            .accessibilityLabel("État de la CI")
    }

    @ViewBuilder
    private func agentStatusRow(for issue: ATraiterIssue) -> some View {
        HStack(spacing: 8) {
            switch issue.agentStatus {
            case .toDo:
                Label("À prendre", systemImage: "tray")
                    .foregroundStyle(.secondary)
            case .inProgress:
                Label("En cours", systemImage: "hammer")
                    .foregroundStyle(.orange)
            case let .pullRequest(number, url, isDraft, ciState):
                Link("PR #\(number)", destination: url)
                ciLabel(for: ciState)
                if isDraft {
                    Text("Brouillon")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                } else {
                    Text("Prête")
                }
            case let .merged(number, url):
                Link(destination: url) {
                    Label("PR #\(number) fusionnée", systemImage: "checkmark.circle")
                }
                .foregroundStyle(.purple)
            case .reportPosted:
                Label("Compte rendu posté", systemImage: "doc.text")
                    .foregroundStyle(.blue)
            case nil:
                EmptyView()
            }
            if issue.hasReport, issue.agentStatus != .reportPosted {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Compte rendu posté")
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func reviewLabel(for decision: String?) -> some View {
        switch decision {
        case "APPROVED": Text("Approuvée")
        case "CHANGES_REQUESTED": Text("Modifs demandées")
        case "REVIEW_REQUIRED": Text("Relecture attendue")
        default: EmptyView()
        }
    }
}

#Preview("Bus echo-scribe") {
    let json = """
    {"bus":{"nodes":[
      {"number":1,"title":"À prendre","url":"https://github.com/vesper-atelier/taches/issues/1","updatedAt":"2026-09-30T10:00:00Z","repository":{"nameWithOwner":"vesper-atelier/taches"}},
      {"number":2,"title":"En cours","url":"https://github.com/vesper-atelier/taches/issues/2","updatedAt":"2026-09-30T09:00:00Z","repository":{"nameWithOwner":"vesper-atelier/taches"},"comments":{"nodes":[{"author":{"login":"echo-scribe"},"body":"Pris en charge","createdAt":"2026-09-30T09:00:00Z"}]}},
      {"number":3,"title":"PR brouillon","url":"https://github.com/vesper-atelier/taches/issues/3","updatedAt":"2026-09-30T08:00:00Z","repository":{"nameWithOwner":"vesper-atelier/taches"},"timelineItems":{"nodes":[{"source":{"number":11,"url":"https://github.com/vesper-atelier/GithubDahboard/pull/11","isDraft":true,"state":"OPEN","commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]}}}]}},
      {"number":4,"title":"PR prête","url":"https://github.com/vesper-atelier/taches/issues/4","updatedAt":"2026-09-30T07:00:00Z","repository":{"nameWithOwner":"vesper-atelier/taches"},"comments":{"nodes":[{"author":{"login":"echo-scribe"},"body":"Conforme : vérifié","createdAt":"2026-09-30T07:00:00Z"}]},"timelineItems":{"nodes":[{"source":{"number":12,"url":"https://github.com/vesper-atelier/GithubDahboard/pull/12","isDraft":false,"state":"OPEN","commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}}]}},
      {"number":5,"title":"PR fusionnée","url":"https://github.com/vesper-atelier/taches/issues/5","updatedAt":"2026-09-30T06:00:00Z","repository":{"nameWithOwner":"vesper-atelier/taches"},"timelineItems":{"nodes":[{"source":{"number":10,"url":"https://github.com/vesper-atelier/GithubDahboard/pull/10","isDraft":false,"state":"MERGED"}}]}}
    ]}}
    """
    let data = try! JSONDecoder().decode(ATraiterData.self, from: Data(json.utf8))
    ATraiterView(data: data, warning: nil)
        .padding()
}
