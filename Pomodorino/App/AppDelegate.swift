import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    private var settings: AppSettings!
    private var pomodoroTimer: PomodoroTimer!
    private var audioManager: AudioManager!
    private var analyticsStore: AnalyticsStore!
    private var taskStore: FocusTaskStore!
    private var shortcutManager: ShortcutManager!
    private var notificationManager: NotificationManager!

    private var cancellables = Set<AnyCancellable>()
    private var statusItemTrackingArea: NSTrackingArea?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var hoverDismissWorkItem: DispatchWorkItem?
    private var popoverPinningState = PopoverPinningState()
    private var popoverWindowMoveObserver: NSObjectProtocol?
    private weak var observedPopoverWindow: NSWindow?
    private var isRestoringPinnedPopoverFrame = false
    private var originalPopoverCollectionBehavior: NSWindow.CollectionBehavior?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize dependencies
        settings = AppSettings()
        audioManager = AudioManager(settings: settings)
        analyticsStore = AnalyticsStore()
        taskStore = FocusTaskStore()
        pomodoroTimer = PomodoroTimer(
            settings: settings,
            audioManager: audioManager,
            analyticsStore: analyticsStore,
            taskStore: taskStore
        )
        notificationManager = NotificationManager()
        notificationManager.requestPermission()

        // Session completion notifications
        pomodoroTimer.onSessionComplete = { [weak self] completedType in
            switch completedType {
            case .work:
                self?.notificationManager.sendNotification(
                    title: "Pomodoro",
                    body: "Great work! Time for a break."
                )
            case .shortBreak, .longBreak:
                self?.notificationManager.sendNotification(
                    title: "Pomodoro",
                    body: "Break is over! Time to focus."
                )
            }
        }

        // Setup status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            installStatusItemTracking(on: button)
        }

        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        // The app owns dismissal so clicks on SwiftUI controls never cause
        // AppKit to close, detach, or recreate the active popover.
        popover.behavior = .applicationDefined
        setPopoverContent(tab: .timer)
        installClickMonitors()

        // Observe timer changes for status bar updates
        pomodoroTimer.$timeRemaining
            .combineLatest(pomodoroTimer.$timerState, pomodoroTimer.$sessionType)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            settings.$accentColor,
            settings.$workTimerColor,
            settings.$breakTimerColor,
            settings.$pausedTimerColor
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateStatusBar()
        }
        .store(in: &cancellables)

        settings.$menuBarPillEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBar()
            }
            .store(in: &cancellables)

        // Setup global keyboard shortcut (⌃⌥P)
        shortcutManager = ShortcutManager()
        shortcutManager.onToggle = { [weak self] in
            self?.pomodoroTimer.toggleStartPause()
        }
        shortcutManager.register(
            keyCode: settings.shortcutKeyCode,
            modifiers: settings.shortcutModifiers
        )
        Publishers.CombineLatest(settings.$shortcutKeyCode, settings.$shortcutModifiers)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keyCode, modifiers in
                self?.shortcutManager.register(keyCode: keyCode, modifiers: modifiers)
            }
            .store(in: &cancellables)

        updateStatusBar()
    }

    private func updateStatusBar() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let symbolColor: NSColor
        let pillColor: NSColor?

        switch pomodoroTimer.timerState {
        case .idle:
            symbolName = "timer"
            symbolColor = .secondaryLabelColor
            pillColor = nil
        case .running:
            if pomodoroTimer.sessionType == .work {
                symbolName = "flame.fill"
                let color = settings.workTimerColor.nsColor
                symbolColor = color
                pillColor = color
            } else {
                symbolName = "leaf.fill"
                let color = settings.breakTimerColor.nsColor
                symbolColor = color
                pillColor = color
            }
        case .paused:
            symbolName = "pause.circle"
            let color = settings.pausedTimerColor.nsColor
            symbolColor = color
            pillColor = color
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pomodoro") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                .applying(.init(paletteColors: [symbolColor]))
            let configuredImage = image.withSymbolConfiguration(config)!
            configuredImage.isTemplate = false
            button.image = configuredImage
        }

        button.title = " \(pomodoroTimer.formattedTime)"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.wantsLayer = true
        if settings.menuBarPillEnabled, let pillColor {
            button.layer?.backgroundColor = pillColor
                .withAlphaComponent(pillColor.alphaComponent * 0.24)
                .cgColor
        } else {
            button.layer?.backgroundColor = NSColor.clear.cgColor
        }
        button.layer?.cornerRadius = settings.menuBarPillEnabled ? 6 : 0
        button.layer?.masksToBounds = true
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        pinPopoverFromStatusItem()
    }

    private func setPopoverContent(tab: PopoverTab) {
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                timer: pomodoroTimer,
                settings: settings,
                analyticsStore: analyticsStore,
                taskStore: taskStore,
                initialTab: tab
            )
        )
    }

    private func installStatusItemTracking(on button: NSStatusBarButton) {
        let trackingArea = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        statusItemTrackingArea = trackingArea
    }

    private func installClickMonitors() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouseDown(at: NSEvent.mouseLocation)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            let point = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.handleMouseDown(at: point)
            }
        }
    }

    @objc private func mouseEntered(with event: NSEvent) {
        guard popoverPinningState.phase == .hidden else { return }
        showPopoverForHover()
    }

    @objc private func mouseExited(with event: NSEvent) {
        guard popoverPinningState.phase == .hoverOpen else { return }

        hoverDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissHoverPopoverIfNeeded()
        }
        hoverDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func showPopoverForHover() {
        guard let button = statusItem.button, !popover.isShown else { return }

        popoverPinningState.openForHover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        recordPopoverFrameAfterPresentation()
    }

    private func pinPopoverFromStatusItem() {
        hoverDismissWorkItem?.cancel()

        guard let button = statusItem.button else { return }

        if popover.isShown {
            // This is the hover-open → pinned transition. The existing
            // popover remains in place; it is never closed or shown again.
            popoverPinningState.pinExistingPopover()
            button.highlight(true)
            lockCurrentPopoverFrameIfPinned()
            return
        }

        _ = popoverPinningState.pin(using: .zero)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        recordPopoverFrameAfterPresentation()
    }

    private func recordPopoverFrameAfterPresentation() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let frame = self.popoverFrame else { return }
            self.popoverPinningState.recordPresentedFrame(frame)
            self.lockCurrentPopoverFrameIfPinned()
        }
    }

    /// Locks the actual popover window frame only after a status-item click
    /// has made the popover interactive. Hover-only presentation stays free
    /// to follow its menu-bar anchor.
    private func lockCurrentPopoverFrameIfPinned() {
        guard
            popoverPinningState.phase == .pinned,
            let frame = popoverFrame,
            let window = popover.contentViewController?.view.window
        else {
            return
        }

        popoverPinningState.recordPresentedFrame(frame)
        configurePinnedFullscreenPresentation(for: window)
        observePinnedPopoverWindowIfNeeded()
    }

    /// A status-item popover's window normally has transient collection
    /// behavior, which makes it follow the menu bar as another app's
    /// full-screen Space hides and reveals it. While pinned, make that same
    /// window an auxiliary stationary window for the active full-screen
    /// Space. The original behavior is restored when the user clicks away.
    private func configurePinnedFullscreenPresentation(for window: NSWindow) {
        if originalPopoverCollectionBehavior == nil {
            originalPopoverCollectionBehavior = window.collectionBehavior
        }

        var behavior = window.collectionBehavior
        behavior.remove(.managed)
        behavior.remove(.transient)
        behavior.remove(.fullScreenPrimary)
        behavior.insert(.stationary)
        behavior.insert(.fullScreenAuxiliary)
        window.collectionBehavior = behavior
    }

    private func observePinnedPopoverWindowIfNeeded() {
        guard let window = popover.contentViewController?.view.window else { return }

        if observedPopoverWindow === window, popoverWindowMoveObserver != nil {
            return
        }

        removePopoverWindowMoveObserver()
        observedPopoverWindow = window
        popoverWindowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.restorePinnedPopoverFrameIfNeeded()
        }
    }

    private func restorePinnedPopoverFrameIfNeeded() {
        guard
            !isRestoringPinnedPopoverFrame,
            let window = observedPopoverWindow,
            let currentFrame = popoverFrame,
            let pinnedFrame = popoverPinningState.frameToRestore(afterAutomaticMoveTo: currentFrame)
        else {
            return
        }

        isRestoringPinnedPopoverFrame = true
        window.setFrame(pinnedFrame, display: true, animate: false)
        isRestoringPinnedPopoverFrame = false
    }

    private func removePopoverWindowMoveObserver() {
        if let popoverWindowMoveObserver {
            NotificationCenter.default.removeObserver(popoverWindowMoveObserver)
        }
        if let window = observedPopoverWindow, let originalPopoverCollectionBehavior {
            window.collectionBehavior = originalPopoverCollectionBehavior
        }
        popoverWindowMoveObserver = nil
        observedPopoverWindow = nil
        originalPopoverCollectionBehavior = nil
    }

    private func dismissHoverPopoverIfNeeded() {
        guard popoverPinningState.phase == .hoverOpen, !isPointerInsidePomodorino else { return }
        closePopover()
    }

    private func handleMouseDown(at point: NSPoint) {
        guard popoverPinningState.phase != .hidden, popover.isShown else { return }

        if isInternalClick(at: point) {
            hoverDismissWorkItem?.cancel()
            if popoverPinningState.phase == .hoverOpen {
                popoverPinningState.pinExistingPopover()
                statusItem.button?.highlight(true)
                lockCurrentPopoverFrameIfPinned()
            }
            // AppKit can schedule status-bar repositioning after a control
            // action. Re-check on the next turn even if no move notification
            // was emitted synchronously.
            DispatchQueue.main.async { [weak self] in
                self?.restorePinnedPopoverFrameIfNeeded()
            }
            return
        }

        closePopover()
    }

    private var isPointerInsidePomodorino: Bool {
        isInternalClick(at: NSEvent.mouseLocation)
    }

    private func isInternalClick(at point: NSPoint) -> Bool {
        // The click which pins a hover-open popover can arrive before AppKit
        // has exposed the popover's NSWindow. The status item is still an
        // internal target in that brief interval, so it must never be treated
        // as an outside click that closes and recreates the popover.
        if let statusItemFrame, statusItemFrame.contains(point) {
            return true
        }

        guard let popoverFrame else { return false }
        return popoverFrame.contains(point)
    }

    private var popoverFrame: NSRect? {
        popover.contentViewController?.view.window?.frame
    }

    private var statusItemFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func closePopover() {
        hoverDismissWorkItem?.cancel()
        removePopoverWindowMoveObserver()
        popover.performClose(nil)
        statusItem.button?.highlight(false)
        popoverPinningState.dismissFromOutsideClick()
    }

    private func showContextMenu() {
        if popover.isShown {
            closePopover()
        }

        let menu = NSMenu()

        let timerItem = NSMenuItem(
            title: timerMenuTitle,
            action: #selector(toggleTimerFromMenu),
            keyEquivalent: ""
        )
        timerItem.target = self
        menu.addItem(timerItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Pomodorino",
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var timerMenuTitle: String {
        switch pomodoroTimer.timerState {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    @objc private func toggleTimerFromMenu() {
        pomodoroTimer.toggleStartPause()
    }

    @objc private func showSettings() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
        }
        setPopoverContent(tab: .settings)
        _ = popoverPinningState.pin(using: .zero)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        recordPopoverFrameAfterPresentation()
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
