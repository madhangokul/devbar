import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @ObservedObject var store: ToolbarStore

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notifyOnSuccess") private var notifyOnSuccess = true
    @AppStorage("notifyOnFailure") private var notifyOnFailure = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DevBarSectionHeader(title: "Notifications", detail: "Local alerts")

                NotificationPreferencesView(compact: true)

                DevBarSectionHeader(title: "Current signals", detail: "\(signalItems.count) visible")

                if signalItems.isEmpty {
                    NotificationEmptyState(notificationsEnabled: notificationsEnabled)
                } else {
                    ForEach(signalItems.prefix(8)) { item in
                        NotificationSignalRow(
                            item: item,
                            isEnabled: notificationEnabled(for: item.status)
                        )
                    }
                }
            }
            .padding(12)
        }
        .accessibilityLabel("Notification center")
    }

    private var signalItems: [ToolbarItem] {
        store.visibleItems
            .filter { $0.status == .error || $0.status == .warning || $0.status == .good }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func notificationEnabled(for status: ItemStatus) -> Bool {
        guard notificationsEnabled else { return false }
        if status == .error { return notifyOnFailure }
        if status == .good { return notifyOnSuccess }
        return false
    }
}

struct NotificationPreferencesView: View {
    var compact = false

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notifyOnSuccess") private var notifyOnSuccess = true
    @AppStorage("notifyOnFailure") private var notifyOnFailure = true
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var authorizationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 13) {
            Toggle("Allow deployment alerts", isOn: notificationBinding)
                .toggleStyle(.switch)
                .font(.subheadline.weight(.medium))
                .accessibilityHint("Requests macOS notification permission when enabled")

            Divider()

            Toggle("Successful deployments", isOn: $notifyOnSuccess)
                .disabled(!notificationsEnabled)
            Toggle("Failed or blocked deployments", isOn: $notifyOnFailure)
                .disabled(!notificationsEnabled)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: permissionIcon)
                    .foregroundStyle(permissionColor)
                    .accessibilityHidden(true)
                Text(permissionMessage)
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .font(.callout)
        .padding(compact ? 12 : 14)
        .devBarCard()
        .task { await refreshAuthorizationStatus() }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { requestedValue in
                if requestedValue {
                    Task { await enableNotifications() }
                } else {
                    notificationsEnabled = false
                    authorizationError = nil
                }
            }
        )
    }

    private var permissionMessage: String {
        if let authorizationError { return authorizationError }
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return notificationsEnabled
                ? "macOS alerts are enabled for the selected events."
                : "Permission is available; DevBar alerts are paused."
        case .denied:
            return "Notifications are blocked in System Settings. DevBar will continue tracking silently."
        case .notDetermined:
            return "macOS asks for permission only when you enable alerts."
        @unknown default:
            return "Notification permission status is unavailable."
        }
    }

    private var permissionIcon: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: "checkmark.circle.fill"
        case .denied: "exclamationmark.circle.fill"
        case .notDetermined: "info.circle.fill"
        @unknown default: "questionmark.circle.fill"
        }
    }

    private var permissionColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: DevBarTheme.healthy
        case .denied: DevBarTheme.failed
        case .notDetermined: DevBarTheme.accent
        @unknown default: DevBarTheme.neutral
        }
    }

    @MainActor
    private func enableNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationsEnabled = granted
            authorizationError = granted ? nil : "macOS notification permission was not granted."
        } catch {
            notificationsEnabled = false
            authorizationError = "Could not request notification permission: \(error.localizedDescription)"
        }
        await refreshAuthorizationStatus()
    }

    @MainActor
    private func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if authorizationStatus == .denied {
            notificationsEnabled = false
        }
    }
}

private struct NotificationSignalRow: View {
    let item: ToolbarItem
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: DevBarTheme.symbol(for: item.status))
                .foregroundStyle(DevBarTheme.color(for: item.status))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(item.groupName) · \(DevBarTheme.label(for: item.phase))")
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.timestamp, style: .relative)
                    .monospacedDigit()
                Text(isEnabled ? "Alert on" : "Silent")
            }
            .font(.caption2)
            .foregroundStyle(isEnabled ? DevBarTheme.accent : DevBarTheme.tertiaryText)
        }
        .padding(10)
        .devBarCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.groupName), \(DevBarTheme.label(for: item.phase)), notifications \(isEnabled ? "enabled" : "silent")")
    }
}

private struct NotificationEmptyState: View {
    let notificationsEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notificationsEnabled ? "bell" : "bell.slash")
                .foregroundStyle(DevBarTheme.tertiaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No deployment signals")
                    .font(.caption.weight(.semibold))
                Text(notificationsEnabled ? "DevBar is ready to notify you." : "Enable alerts above when you are ready.")
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
