import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ToolbarStore

    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }

            ProvidersSettingsPane(store: store)
                .tabItem { Label("Providers", systemImage: "link") }

            NotificationSettingsPane()
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .padding(20)
        .frame(width: 560, height: 470)
        .foregroundStyle(DevBarTheme.primaryText)
        .background(DevBarTheme.background)
        .preferredColorScheme(.dark)
    }
}

private struct GeneralSettingsPane: View {
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Refresh deployments automatically", isOn: $autoRefreshEnabled)
                Text("DevBar checks more often while work is active and backs off when everything is settled.")
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }

            Section("Startup") {
                LaunchAtLoginToggle()
            }

            Section("Privacy & permissions") {
                PermissionRow(
                    icon: "network",
                    title: "Network access",
                    detail: "Connects only to configured provider APIs."
                )
                PermissionRow(
                    icon: "key.fill",
                    title: "Keychain",
                    detail: "Stores provider tokens locally and securely."
                )
                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "No elevated access",
                    detail: "No administrator, disk, screen, camera, or accessibility permission is required."
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("General settings")
    }
}

private struct ProvidersSettingsPane: View {
    @ObservedObject var store: ToolbarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Connected providers")
                    .font(.title3.weight(.semibold))
                Text("Tokens stay in your Mac Keychain and are sent only to the provider you configure.")
                    .font(.callout)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.providers, id: \.id) { provider in
                        ProviderSettingsRow(provider: provider, store: store)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityLabel("Provider settings")
    }
}

private struct NotificationSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Deployment alerts")
                    .font(.title3.weight(.semibold))
                Text("Choose which status changes can create local macOS notifications.")
                    .font(.callout)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }

            NotificationPreferencesView()
            Spacer()
        }
        .accessibilityLabel("Notification settings")
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle("Launch DevBar at login", isOn: binding)
                .accessibilityHint("Registers DevBar in macOS Login Items")
            Text("You can also manage this later in System Settings › General › Login Items.")
                .font(.caption)
                .foregroundStyle(DevBarTheme.secondaryText)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.failed)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    isEnabled = newValue
                    errorMessage = nil
                } catch {
                    isEnabled = SMAppService.mainApp.status == .enabled
                    errorMessage = error.localizedDescription
                }
            }
        )
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(DevBarTheme.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DevBarTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
