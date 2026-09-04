import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct DevBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = DevBarRuntime()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: runtime.store,
                requestRefresh: {
                    Task { await runtime.coordinator.requestRefresh(.manual) }
                }
            )
            .onAppear {
                Task { await runtime.coordinator.setPopoverOpen(true) }
            }
            .onDisappear {
                Task { await runtime.coordinator.setPopoverOpen(false) }
            }
        } label: {
            RuntimeMenuBarIcon(
                store: runtime.store,
                runtime: runtime
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: runtime.store)
        }
    }
}

private struct RuntimeMenuBarIcon: View {
    @ObservedObject var store: ToolbarStore
    let runtime: DevBarRuntime

    @AppStorage(RefreshCoordinator.autoRefreshEnabledKey) private var autoRefreshEnabled = true

    var body: some View {
        MenuBarIconView(
            status: store.aggregateStatus,
            issueCount: store.issueCount
        )
        .task {
            await runtime.start()
            await runtime.coordinator.setAutoRefreshEnabled(autoRefreshEnabled)
        }
        .onChange(of: autoRefreshEnabled) { enabled in
            Task { await runtime.coordinator.setAutoRefreshEnabled(enabled) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            Task { await runtime.coordinator.requestRefresh(.wake) }
        }
    }
}
