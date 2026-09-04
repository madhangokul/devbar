import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: DevBarRuntime?
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let runtime = DevBarRuntime()
        let settingsWindowController = SettingsWindowController(store: runtime.store)
        let statusBarController = StatusBarController(
            runtime: runtime,
            openSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            }
        )

        self.runtime = runtime
        self.settingsWindowController = settingsWindowController
        self.statusBarController = statusBarController

        Task {
            await runtime.start()
            await runtime.coordinator.setAutoRefreshEnabled(
                UserDefaults.standard.object(forKey: RefreshCoordinator.autoRefreshEnabledKey) as? Bool ?? true
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.stop()
        guard let runtime else { return }
        Task { await runtime.stop() }
    }
}

@main
struct DevBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
