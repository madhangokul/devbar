import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let runtime: DevBarRuntime
    private let statusItem: NSStatusItem
    private let panel: DevBarPanel
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var wakeObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var isPanelVisible = false

    init(runtime: DevBarRuntime, openSettings: @escaping () -> Void) {
        self.runtime = runtime
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = DevBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()
        configureStatusItem()
        configurePanel(openSettings: openSettings)
        observeRuntime()
    }

    func stop() {
        removeClickMonitors()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePanel() {
        isPanelVisible ? hidePanel() : showPanel()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageLeading
        updateStatusItem()
    }

    private func configurePanel(openSettings: @escaping () -> Void) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let content = MenuBarContentView(
            store: runtime.store,
            requestRefresh: { [weak runtime] in
                guard let runtime else { return }
                Task { await runtime.coordinator.requestRefresh(.manual) }
            }
        )
        .environment(\.openDevBarSettings, { [weak self] in
            self?.hidePanel(animated: false)
            openSettings()
        })
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }

        panel.contentViewController = NSHostingController(rootView: content)
    }

    private func observeRuntime() {
        runtime.store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak runtime] _ in
            guard let runtime else { return }
            Task { await runtime.coordinator.requestRefresh(.wake) }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak runtime] _ in
            guard let runtime else { return }
            let enabled = UserDefaults.standard.object(
                forKey: RefreshCoordinator.autoRefreshEnabledKey
            ) as? Bool ?? true
            Task { await runtime.coordinator.setAutoRefreshEnabled(enabled) }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "DevBar")
        image?.isTemplate = true
        button.image = image
        button.title = runtime.store.issueCount > 0 ? " \(runtime.store.issueCount)" : ""
        button.toolTip = "DevBar — \(runtime.store.aggregateStatus.label)"
        button.contentTintColor = statusColor
        button.setAccessibilityLabel("DevBar, \(runtime.store.aggregateStatus.label)")
    }

    private var statusColor: NSColor {
        switch runtime.store.aggregateStatus {
        case .good: .systemGreen
        case .warning: .systemOrange
        case .error: .systemRed
        case .neutral: .secondaryLabelColor
        }
    }

    private func showPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        let inset: CGFloat = 8
        let finalX = min(
            max(screen.visibleFrame.minX + inset, buttonFrame.midX - panelSize.width / 2),
            screen.visibleFrame.maxX - panelSize.width - inset
        )
        let finalY = buttonFrame.minY - panelSize.height - 7
        let finalFrame = NSRect(origin: NSPoint(x: finalX, y: finalY), size: panelSize)

        isPanelVisible = true
        panel.alphaValue = 0
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 6), display: false)
        panel.makeKeyAndOrderFront(nil)
        installClickMonitors()
        Task { await runtime.coordinator.setPopoverOpen(true) }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func hidePanel(animated: Bool = true) {
        guard isPanelVisible else { return }
        isPanelVisible = false
        removeClickMonitors()
        Task { await runtime.coordinator.setPopoverOpen(false) }

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        let hiddenFrame = panel.frame.offsetBy(dx: 0, dy: 4)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func installClickMonitors() {
        removeClickMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                hidePanel()
                return nil
            }
            if event.window !== panel, event.window !== statusItem.button?.window {
                hidePanel()
            }
            return event
        }
    }

    private func removeClickMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }
}

private final class DevBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: ToolbarStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DevBar Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("DevBarSettingsWindow")
        window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
