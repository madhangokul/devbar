import AppKit
import Combine
import OSLog
import QuartzCore
import SwiftUI

private let overlayLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.github.madhangokul.devbar",
    category: "DeploymentHUD"
)

@MainActor
final class StatusBarController: NSObject {
    private enum PanelState {
        case closed
        case opening
        case open
        case closing
    }

    private let runtime: DevBarRuntime
    private let statusItem: NSStatusItem
    private let panel: DevBarPanel
    private let deploymentOverlayPanel: DevBarPanel
    private let deploymentOverlayModel = DeploymentOverlayModel()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var wakeObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var panelState: PanelState = .closed
    private var panelTransitionID = 0
    private var deploymentOverlayTracker: DeploymentOverlayTracker
    private var dismissedOverlayIDs: [String] = []
    private var overlayDismissTask: Task<Void, Never>?
    private var observedAutoRefreshEnabled = UserDefaults.standard.object(
        forKey: RefreshCoordinator.autoRefreshEnabledKey
    ) as? Bool ?? true

    init(runtime: DevBarRuntime, openSettings: @escaping () -> Void) {
        self.runtime = runtime
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = DevBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        deploymentOverlayPanel = DevBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 174),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        deploymentOverlayTracker = DeploymentOverlayTracker(initialItems: runtime.store.items)

        super.init()
        configureStatusItem()
        configurePanel(openSettings: openSettings)
        configureDeploymentOverlay()
        observeRuntime()
    }

    func stop() {
        removeClickMonitors()
        overlayDismissTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePanel() {
        hideDeploymentOverlay(animated: false)
        switch panelState {
        case .closed, .closing: showPanel()
        case .opening, .open: hidePanel()
        }
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

    private func configureDeploymentOverlay() {
        deploymentOverlayPanel.isOpaque = false
        deploymentOverlayPanel.backgroundColor = .clear
        deploymentOverlayPanel.hasShadow = false
        deploymentOverlayPanel.level = .popUpMenu
        deploymentOverlayPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        deploymentOverlayPanel.isMovable = false
        deploymentOverlayPanel.isReleasedWhenClosed = false
        deploymentOverlayPanel.animationBehavior = .none
        deploymentOverlayPanel.contentViewController = NSHostingController(
            rootView: DeploymentOverlayHost(
                model: deploymentOverlayModel,
                onDismiss: { [weak self] in self?.dismissCurrentDeploymentOverlay() },
                onOpenSite: { [weak self] url in
                    NSWorkspace.shared.open(url)
                    self?.hideDeploymentOverlay()
                }
            )
        )
    }

    private func observeRuntime() {
        runtime.store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        runtime.store.$lastUpdated
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileDeploymentOverlay()
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
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItem()
                let enabled = UserDefaults.standard.object(
                    forKey: RefreshCoordinator.autoRefreshEnabledKey
                ) as? Bool ?? true
                guard enabled != self.observedAutoRefreshEnabled else { return }
                self.observedAutoRefreshEnabled = enabled
                await self.runtime.coordinator.setAutoRefreshEnabled(enabled)
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "DevBar")
        image?.isTemplate = true
        button.image = image
        let attentionCount = DeploymentAttention.attentionCount(
            items: runtime.store.items,
            providerErrors: runtime.store.providerErrors
        )
        let displayStatus = DeploymentAttention.displayStatus(
            items: runtime.store.items,
            providerErrors: runtime.store.providerErrors
        )
        button.title = attentionCount > 0 ? " \(attentionCount)" : ""
        button.toolTip = "DevBar — \(displayStatus.label)"
        button.contentTintColor = statusColor
        button.setAccessibilityLabel("DevBar, \(displayStatus.label)")
    }

    private var statusColor: NSColor {
        switch DeploymentAttention.displayStatus(
            items: runtime.store.items,
            providerErrors: runtime.store.providerErrors
        ) {
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

        panelTransitionID += 1
        let transitionID = panelTransitionID
        let wasClosed = panelState == .closed
        panelState = .opening
        if wasClosed {
            panel.alphaValue = 0
            panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 6), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        installClickMonitors()
        Task { await runtime.coordinator.setPopoverOpen(true) }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.panelTransitionID == transitionID else { return }
                self.panelState = .open
            }
        }
    }

    private func reconcileDeploymentOverlay() {
        let currentItems = runtime.store.items
        let currentByID = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0) })
        let candidate = deploymentOverlayTracker.consume(
            currentItems,
            excluding: Set(dismissedOverlayIDs)
        )

        if let displayedID = deploymentOverlayModel.item?.id,
           let updatedItem = currentByID[displayedID] {
            let oldPhase = deploymentOverlayModel.item?.phase
            deploymentOverlayModel.item = updatedItem
            if oldPhase?.isActive == true, !updatedItem.phase.isActive {
                scheduleOverlayDismiss(after: updatedItem.phase == .ready ? 12 : 15)
            }
            return
        }

        guard let candidate else { return }
        guard panelState == .closed else {
            overlayLogger.debug("Deployment HUD suppressed because the main tray is already visible")
            return
        }
        deploymentOverlayModel.item = candidate
        overlayLogger.info("Showing deployment HUD for phase \(candidate.phase.rawValue, privacy: .public)")
        showDeploymentOverlay()
        if !candidate.phase.isActive {
            scheduleOverlayDismiss(after: candidate.phase == .ready ? 12 : 15)
        }
    }

    private func showDeploymentOverlay() {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else {
            overlayLogger.error("Could not present deployment HUD because the menu bar anchor is unavailable")
            return
        }

        overlayDismissTask?.cancel()
        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let size = deploymentOverlayPanel.frame.size
        let inset: CGFloat = 8
        let x = min(
            max(screen.visibleFrame.minX + inset, buttonFrame.midX - size.width / 2),
            screen.visibleFrame.maxX - size.width - inset
        )
        let finalFrame = NSRect(
            origin: NSPoint(x: x, y: buttonFrame.minY - size.height - 7),
            size: size
        )

        deploymentOverlayPanel.alphaValue = 0
        deploymentOverlayPanel.setFrame(finalFrame.offsetBy(dx: 0, dy: 6), display: false)
        deploymentOverlayPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            deploymentOverlayPanel.animator().alphaValue = 1
            deploymentOverlayPanel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func dismissCurrentDeploymentOverlay() {
        if let id = deploymentOverlayModel.item?.id {
            dismissedOverlayIDs.removeAll { $0 == id }
            dismissedOverlayIDs.append(id)
            dismissedOverlayIDs = Array(dismissedOverlayIDs.suffix(50))
        }
        hideDeploymentOverlay()
    }

    private func scheduleOverlayDismiss(after delay: TimeInterval) {
        overlayDismissTask?.cancel()
        overlayDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hideDeploymentOverlay() }
        }
    }

    private func hideDeploymentOverlay(animated: Bool = true) {
        overlayDismissTask?.cancel()
        guard deploymentOverlayPanel.isVisible else { return }
        guard animated else {
            deploymentOverlayPanel.orderOut(nil)
            deploymentOverlayPanel.alphaValue = 1
            deploymentOverlayModel.item = nil
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            deploymentOverlayPanel.animator().alphaValue = 0
            deploymentOverlayPanel.animator().setFrame(
                deploymentOverlayPanel.frame.offsetBy(dx: 0, dy: 4),
                display: true
            )
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.deploymentOverlayPanel.orderOut(nil)
                self?.deploymentOverlayPanel.alphaValue = 1
                self?.deploymentOverlayModel.item = nil
            }
        }
    }

    private func hidePanel(animated: Bool = true) {
        guard panelState != .closed else { return }
        panelTransitionID += 1
        let transitionID = panelTransitionID
        panelState = .closing
        removeClickMonitors()
        Task { await runtime.coordinator.setPopoverOpen(false) }

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            panelState = .closed
            return
        }

        let hiddenFrame = panel.frame.offsetBy(dx: 0, dy: 4)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.panelTransitionID == transitionID else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panelState = .closed
            }
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

@MainActor
private final class DeploymentOverlayModel: ObservableObject {
    @Published var item: ToolbarItem?
}

private struct DeploymentOverlayHost: View {
    @ObservedObject var model: DeploymentOverlayModel
    let onDismiss: () -> Void
    let onOpenSite: (URL) -> Void

    var body: some View {
        if let item = model.item {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = elapsedDuration(for: item, at: context.date)
                let estimate = item.estimatedBuildDuration ?? 0
                DeploymentProgressOverlay(
                    item: item,
                    estimatedProgress: progress(for: item, elapsed: elapsed, estimate: estimate),
                    elapsedDuration: elapsed,
                    estimatedDuration: estimate,
                    siteURL: item.siteURL,
                    onDismiss: onDismiss,
                    onOpenSite: item.siteURL.map { url in { onOpenSite(url) } }
                )
            }
        }
    }

    private func elapsedDuration(for item: ToolbarItem, at now: Date) -> TimeInterval {
        item.completedBuildDuration ?? item.currentBuildElapsed(at: now) ?? item.triggerAge(at: now)
    }

    private func progress(for item: ToolbarItem, elapsed: TimeInterval, estimate: TimeInterval) -> Double {
        if item.phase == .ready { return 1 }
        if item.phase.isFailure { return min(1, max(0.08, estimate > 0 ? elapsed / estimate : 0.5)) }
        if estimate > 0 { return min(0.98, max(0.04, elapsed / estimate)) }
        if item.phase == .queued { return 0.04 }
        return min(0.85, 0.12 + (elapsed / 180) * 0.73)
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
