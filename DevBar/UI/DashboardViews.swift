import AppKit
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: ToolbarStore

    @AppStorage("dismissedFailureDeploymentIDs") private var dismissedFailureIDs = ""

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HealthSummaryCard(
                    status: store.aggregateStatus,
                    projectCount: projectNames.count,
                    activeCount: activeItems.count,
                    failureCount: failedItems.count
                )

                if !visibleFailedItems.isEmpty {
                    AttentionCard(items: visibleFailedItems, onDismiss: dismissFailure)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    MetricCard(
                        title: "Recent",
                        value: "\(store.visibleItems.count)",
                        detail: "in current project scope",
                        icon: "waveform.path.ecg",
                        color: DevBarTheme.accent
                    )
                    MetricCard(
                        title: "In progress",
                        value: "\(activeItems.count)",
                        detail: "building or queued",
                        icon: "clock.fill",
                        color: DevBarTheme.active
                    )
                    MetricCard(
                        title: "Projects",
                        value: "\(projectNames.count)",
                        detail: "in current scope",
                        icon: "shippingbox.fill",
                        color: DevBarTheme.accent
                    )
                    MetricCard(
                        title: "Failed",
                        value: "\(failedItems.count)",
                        detail: "failed, blocked, canceled",
                        icon: "exclamationmark.triangle.fill",
                        color: failedItems.isEmpty ? DevBarTheme.healthy : DevBarTheme.failed
                    )
                }

                ForEach(errorProviders, id: \.id) { provider in
                    ProviderErrorBanner(
                        providerName: provider.displayName,
                        message: store.providerErrors[provider.id] ?? "Could not refresh."
                    )
                }

                DevBarSectionHeader(title: "Live deployments", detail: "Newest first")

                if store.visibleItems.isEmpty {
                    InlineEmptyState(
                        icon: "tray",
                        title: "No deployments found",
                        message: "Refresh DevBar or adjust your project filter."
                    )
                } else {
                    ForEach(store.visibleItems.prefix(6)) { item in
                        ItemRow(item: item, compact: true)
                    }
                }
            }
            .padding(12)
        }
        .accessibilityLabel("Deployment overview")
        .onAppear(perform: synchronizeDismissals)
        .onChange(of: store.items) { _ in synchronizeDismissals() }
    }

    private var projectNames: Set<String> {
        Set(store.visibleItems.map(\.groupName))
    }

    private var activeItems: [ToolbarItem] {
        store.visibleItems.filter { $0.phase.isActive }
    }

    private var failedItems: [ToolbarItem] {
        store.visibleItems.filter { $0.phase.isFailure }
    }

    private var visibleFailedItems: [ToolbarItem] {
        let dismissed = Set(dismissedFailureIDs.split(separator: "\n").map(String.init))
        return failedItems.filter { !dismissed.contains($0.id) }
    }

    private var errorProviders: [any ToolbarProvider] {
        store.enabledProviders.filter { store.providerErrors[$0.id] != nil }
    }

    private func dismissFailure(_ id: String) {
        var ids = dismissedFailureIDs.split(separator: "\n").map(String.init)
        ids.removeAll { $0 == id }
        ids.append(id)
        dismissedFailureIDs = ids.suffix(50).joined(separator: "\n")
    }

    private func synchronizeDismissals() {
        let currentFailureIDs = Set(store.items.filter { $0.phase.isFailure }.map(\.id))
        let retained = dismissedFailureIDs
            .split(separator: "\n")
            .map(String.init)
            .filter { currentFailureIDs.contains($0) }
            .suffix(50)
        let normalized = retained.joined(separator: "\n")
        if normalized != dismissedFailureIDs {
            dismissedFailureIDs = normalized
        }
    }
}

struct ProjectsView: View {
    @ObservedObject var store: ToolbarStore

    var body: some View {
        VStack(spacing: 0) {
            ProjectFilterBar(store: store)

            if summaries.isEmpty {
                DevBarEmptyState(
                    icon: "shippingbox",
                    title: "No projects yet",
                    message: "Projects appear here after the first successful Vercel refresh."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(summaries) { summary in
                            ProjectSummaryCard(summary: summary)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .accessibilityLabel("Projects")
    }

    private var summaries: [ProjectSummary] {
        let grouped = Dictionary(grouping: store.visibleItems, by: \.groupName)
        return grouped.map { name, items in
            ProjectSummary(name: name, items: items.sorted { $0.timestamp > $1.timestamp })
        }
        .sorted { left, right in
            let leftDate = left.items.first?.timestamp ?? .distantPast
            let rightDate = right.items.first?.timestamp ?? .distantPast
            return leftDate > rightDate
        }
    }
}

struct QueueView: View {
    @ObservedObject var store: ToolbarStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deployment queue")
                        .font(.headline)
                        .foregroundStyle(DevBarTheme.primaryText)
                    Text("Building, initializing, and queued work")
                        .font(.caption)
                        .foregroundStyle(DevBarTheme.secondaryText)
                }
                Spacer()
                Text("\(queuedItems.count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(queuedItems.isEmpty ? DevBarTheme.healthy : DevBarTheme.active)
                    .accessibilityLabel("\(queuedItems.count) active or queued deployments")
            }
            .padding(12)
            .background(DevBarTheme.elevated)
            .overlay(alignment: .bottom) { Divider().overlay(DevBarTheme.border) }

            if queuedItems.isEmpty {
                DevBarEmptyState(
                    icon: "checkmark.circle.fill",
                    iconColor: DevBarTheme.healthy,
                    title: "Queue is clear",
                    message: "No deployments are building or waiting right now."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(queuedItems) { item in
                            QueueItemRow(item: item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .accessibilityLabel("Deployment queue")
    }

    private var queuedItems: [ToolbarItem] {
        store.visibleItems
            .filter { $0.phase.isActive }
            .sorted { left, right in
                if left.phase == right.phase { return left.timestamp < right.timestamp }
                return queuePriority(left.phase) < queuePriority(right.phase)
            }
    }

    private func queuePriority(_ phase: ItemPhase) -> Int {
        switch phase {
        case .building: 0
        case .initializing: 1
        case .queued: 2
        default: 3
        }
    }
}

private struct HealthSummaryCard: View {
    let status: ItemStatus
    let projectCount: Int
    let activeCount: Int
    let failureCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: DevBarTheme.symbol(for: status))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DevBarTheme.color(for: status))
                .frame(width: 38, height: 38)
                .background(DevBarTheme.color(for: status).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Deployment health")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DevBarTheme.secondaryText)
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(DevBarTheme.primaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(projectCount) project\(projectCount == 1 ? "" : "s")")
                Text("\(activeCount) active · \(failureCount) failed")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(DevBarTheme.secondaryText)
        }
        .padding(12)
        .devBarCard(highlighted: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deployment health: \(statusTitle). \(projectCount) projects. \(activeCount) active and \(failureCount) failed deployments.")
    }

    private var statusTitle: String {
        switch status {
        case .good: "Everything is healthy"
        case .warning: "Deployments in progress"
        case .error:
            failureCount > 0
                ? "\(failureCount) deployment\(failureCount == 1 ? "" : "s") failed"
                : "Provider connection issue"
        case .neutral: "Waiting for data"
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(DevBarTheme.primaryText)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DevBarTheme.secondaryText)
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(DevBarTheme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .devBarCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value), \(detail)")
    }
}

private struct ProjectFilterBar: View {
    @ObservedObject var store: ToolbarStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(DevBarTheme.secondaryText)
                .accessibilityHidden(true)
            Picker("Project", selection: $store.selectedGroupName) {
                Text("All projects").tag(String?.none)
                ForEach(store.availableGroups, id: \.self) { group in
                    Text(group).tag(Optional(group))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if store.selectedGroupName != nil {
                Button {
                    store.selectedGroupName = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DevBarTheme.secondaryText)
                .help("Clear project filter")
                .accessibilityLabel("Clear project filter")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(DevBarTheme.elevated)
        .overlay(alignment: .bottom) { Divider().overlay(DevBarTheme.border) }
    }
}

private struct ProjectSummary: Identifiable {
    let name: String
    let items: [ToolbarItem]

    var id: String { name }
    var latest: ToolbarItem? { items.first }
    var worstStatus: ItemStatus { items.map(\.status).max() ?? .neutral }
}

private struct ProjectSummaryCard: View {
    let summary: ProjectSummary

    @State private var isHovered = false

    var body: some View {
        Button(action: openLatest) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: DevBarTheme.symbol(for: summary.worstStatus))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DevBarTheme.color(for: summary.worstStatus))
                        .accessibilityHidden(true)
                    Text(summary.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DevBarTheme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    if let latest = summary.latest {
                        Text(latest.timestamp, style: .relative)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DevBarTheme.tertiaryText)
                    }
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DevBarTheme.tertiaryText)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 6) {
                    ForEach(Array(summary.items.prefix(8).enumerated()), id: \.element.id) { index, item in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DevBarTheme.color(for: item.status))
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                            .accessibilityHidden(true)
                            .help("Deployment \(index + 1): \(item.status.label)")
                    }
                }

                HStack {
                    Text(summary.latest?.subtitle.isEmpty == false ? summary.latest?.subtitle ?? "" : "Latest deployment")
                        .lineLimit(1)
                    Spacer()
                    Text("\(summary.items.count) recent")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(DevBarTheme.secondaryText)
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProjectCardButtonStyle(isHovered: isHovered))
        .disabled(summary.latest?.openURL == nil)
        .onHover { isHovered = $0 }
        .help(summary.latest?.openURL == nil ? "No project link available" : "Open latest deployment")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.name), \(summary.worstStatus.label), \(summary.items.count) recent deployments")
        .accessibilityHint("Opens the latest deployment in your browser")
    }

    private func openLatest() {
        guard let url = summary.latest?.openURL else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProjectCardButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? DevBarTheme.surfacePressed
                    : (isHovered ? DevBarTheme.surface : DevBarTheme.elevated),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovered ? DevBarTheme.accent.opacity(0.65) : DevBarTheme.border, lineWidth: 1)
            }
    }
}

private struct QueueItemRow: View {
    let item: ToolbarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: DevBarTheme.symbol(for: item.phase))
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.active)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.timestamp, style: .relative)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DevBarTheme.tertiaryText)
            }
            HStack {
                Text(item.groupName)
                    .foregroundStyle(DevBarTheme.accent)
                Spacer()
                Text(DevBarTheme.label(for: item.phase))
                    .foregroundStyle(DevBarTheme.active)
            }
            .font(.caption)
        }
        .padding(11)
        .devBarCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.groupName), \(DevBarTheme.label(for: item.phase)), started \(item.timestamp.formatted(.relative(presentation: .named)))")
    }
}

struct ProviderErrorBanner: View {
    let providerName: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DevBarTheme.failed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(providerName) unavailable")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DevBarTheme.primaryText)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(DevBarTheme.failed.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(DevBarTheme.failed.opacity(0.50), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DevBarLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(DevBarTheme.accent)
            Text("Checking Vercel…")
                .font(.subheadline)
                .foregroundStyle(DevBarTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading deployments from Vercel")
    }
}

struct DevBarEmptyState: View {
    let icon: String
    var iconColor = DevBarTheme.accent
    let title: String
    let message: String
    var showsSettingsButton = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(DevBarTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
            if showsSettingsButton {
                DevBarSettingsLink {
                    Text("Open Settings")
                }
                .buttonStyle(.borderedProminent)
                .tint(DevBarTheme.accent)
                .accessibilityHint("Opens provider settings")
            }
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

private struct InlineEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(DevBarTheme.tertiaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DevBarTheme.primaryText)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }
            Spacer()
        }
        .padding(11)
        .devBarCard()
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(DevBarTheme.accent)
                .frame(width: 48, height: 48)
                .background(DevBarTheme.elevated, in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(DevBarTheme.border, lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Connect Vercel")
                    .font(.title3.weight(.semibold))
                Text("Add a read-only access token to see live deployments, project history, and queue activity.")
                    .font(.callout)
                    .foregroundStyle(DevBarTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }

            DevBarSettingsLink {
                Label("Add Vercel token", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(DevBarTheme.accent)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Opens secure provider settings")

            Text("Credentials are stored in your Mac Keychain.")
                .font(.caption2)
                .foregroundStyle(DevBarTheme.tertiaryText)
        }
        .padding(28)
        .accessibilityElement(children: .contain)
    }
}
