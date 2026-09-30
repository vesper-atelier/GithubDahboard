import SwiftUI

struct ATraiterView: View {
    let data: ATraiterData?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pullRequestsSection
            issuesSection(title: "Bus echo-scribe", issues: data?.busIssues ?? [])
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
                        ForEach(group.pullRequests) { pullRequest in
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
                    }
                }
            } else {
                emptyMessage
            }
        }
    }

    @ViewBuilder
    private func issuesSection(title: String, issues: [ATraiterIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if issues.isEmpty {
                emptyMessage
            } else {
                ForEach(issues) { issue in
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
    private func reviewLabel(for decision: String?) -> some View {
        switch decision {
        case "APPROVED": Text("Approuvée")
        case "CHANGES_REQUESTED": Text("Modifs demandées")
        case "REVIEW_REQUIRED": Text("Relecture attendue")
        default: EmptyView()
        }
    }
}
