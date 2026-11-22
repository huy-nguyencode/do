import SwiftUI

struct OverviewSummary: View {
    let total: Int
    let groups: [OverviewSection: Int]
    let theme: WorkspaceTheme
    let navigate: (TaskView) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.md) {
                totalMetric
                Divider()
                dayMetric
                Divider()
                upcomingMetric
                Divider()
                completedMetric
            }

            VStack(spacing: Space.sm) {
                HStack(spacing: Space.md) {
                    totalMetric
                    dayMetric
                }
                HStack(spacing: Space.md) {
                    upcomingMetric
                    completedMetric
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview summary")
    }

    private var totalMetric: some View { SummaryMetric(count: total, title: "Total", theme: theme) }
    private var dayMetric: some View { link(.today, group: .today, title: "Due today") }
    private var upcomingMetric: some View { link(.upcoming, group: .upcoming, title: "Upcoming") }
    private var completedMetric: some View { link(.completed, group: .completed, title: "Completed") }

    private func link(_ view: TaskView, group: OverviewSection, title: String) -> some View {
        Button { navigate(view) } label: {
            SummaryMetric(count: groups[group, default: 0], title: title, theme: theme)
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .help(view.title)
    }
}

private struct SummaryMetric: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let title: String
    let theme: WorkspaceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(count, format: .number)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : WorkspaceMotion.feedback, value: count)
                .workspaceType(.panel)
                .monospacedDigit()
                .foregroundStyle(theme.ink)
            Text(title)
                .workspaceType(.metadata)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count)")
    }
}
