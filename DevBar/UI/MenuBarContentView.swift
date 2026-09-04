import AppKit
import SwiftUI

enum DevBarSection: String, CaseIterable, Identifiable {
    case overview
    case projects
    case queue
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .queue: "Queue"
        case .notifications: "Notifications"
        }
    }

    var accessibilityTitle: String { title }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .projects: "shippingbox.fill"
        case .queue: "list.bullet.rectangle"
        case .notifications: "bell.fill"
        }
    }

    var shortcut: Character {
        switch self {
        case .overview: "1"
        case .projects: "2"
        case .queue: "3"
        case .notifications: "4"
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var store: ToolbarStore
    let requestRefresh: () -> Void

    @State private var selection: DevBarSection = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().overlay(DevBarTheme.border)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 430, height: 600)
        .foregroundStyle(DevBarTheme.primaryText)
        .background(DevBarTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DevBarTheme.accent)
                .frame(width: 34, height: 34)
                .background(DevBarTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DevBarTheme.border, lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DevBar")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Image(systemName: DevBarTheme.symbol(for: store.aggregateStatus))
                        .font(.caption)
                        .foregroundStyle(DevBarTheme.color(for: store.aggregateStatus))
                        .accessibilityHidden(true)
                }
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("DevBar, \(store.aggregateStatus.label). \(statusSummary)")

            Spacer()

            Button {
                requestRefresh()
            } label: {
                Image(systemName: store.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
            }
            .buttonStyle(DevBarIconButtonStyle())
            .disabled(store.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh deployments (Command-R)")
            .accessibilityLabel(store.isRefreshing ? "Refreshing deployments" : "Refresh deployments")

            DevBarSettingsLink {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(DevBarIconButtonStyle())
            .help("Open DevBar settings")
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(DevBarSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(section.title)
                            .font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 43)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DevBarTabButtonStyle(isSelected: selection == section))
                .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                .accessibilityLabel(section.accessibilityTitle)
                .accessibilityValue(selection == section ? "Selected" : "")
                .help("\(section.accessibilityTitle) (Command-\(String(section.shortcut)))")
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DevBar sections")
    }

    @ViewBuilder
    private var content: some View {
        if store.isRefreshing && store.items.isEmpty && store.providerErrors.isEmpty {
            DevBarLoadingView()
        } else if store.enabledProviders.isEmpty {
            DevBarEmptyState(
                icon: "power",
                title: "No providers enabled",
                message: "Enable Vercel in Settings to begin monitoring deployments.",
                showsSettingsButton: true
            )
        } else if needsOnboarding {
            OnboardingView()
        } else {
            switch selection {
            case .overview:
                OverviewView(store: store)
            case .projects:
                ProjectsView(store: store)
            case .queue:
                QueueView(store: store)
            case .notifications:
                NotificationsView(store: store)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.isRefreshing ? DevBarTheme.active : DevBarTheme.color(for: store.aggregateStatus))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            if let lastUpdated = store.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative)")
            } else {
                Text("Waiting for first refresh")
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
                .foregroundStyle(DevBarTheme.secondaryText)
                .help("Quit DevBar (Command-Q)")
        }
        .font(.caption2)
        .foregroundStyle(DevBarTheme.tertiaryText)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(DevBarTheme.elevated.opacity(0.78))
        .overlay(alignment: .top) { Divider().overlay(DevBarTheme.border) }
    }

    private var needsOnboarding: Bool {
        guard store.items.isEmpty else { return false }
        return store.enabledProviders.allSatisfy { provider in
            let credentials = CredentialStore.credentials(for: provider)
            return provider.credentialFields.contains { field in
                field.isRequired && credentials[field.key, default: ""].isEmpty
            }
        }
    }

    private var statusSummary: String {
        switch store.aggregateStatus {
        case .good: "All tracked deployments are healthy"
        case .warning: "\(activeCount) deployment\(activeCount == 1 ? "" : "s") active"
        case .error: "\(store.issueCount) item\(store.issueCount == 1 ? "" : "s") need attention"
        case .neutral: "Connect Vercel to begin"
        }
    }

    private var activeCount: Int {
        store.items.filter { $0.phase.isActive }.count
    }
}

private struct DevBarTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? DevBarTheme.primaryText : DevBarTheme.secondaryText)
            .background(
                isSelected
                    ? DevBarTheme.surface
                    : (configuration.isPressed ? DevBarTheme.elevated : Color.clear),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(DevBarTheme.accent)
                        .frame(width: 24, height: 2)
                        .padding(.bottom, 1)
                }
            }
    }
}

struct DevBarSettingsLink<Label: View>: View {
    private let label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink { label() }
            } else {
                Button(action: openLegacySettings) { label() }
            }
        }
    }

    private func openLegacySettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
