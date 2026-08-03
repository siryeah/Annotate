import Carbon
import Cocoa
import KeyboardShortcuts
import Sparkle
import SwiftUI

@MainActor
final class PresentationKeyForwarder {
    struct Target: Equatable {
        let processIdentifier: pid_t
        let applicationName: String
    }

    enum ForwardingResult: Equatable {
        case notHandled
        case consumed
        case forwarded(String)
        case permissionRequired
        case targetUnavailable
    }

    typealias TargetProvider = @MainActor () -> Target?
    typealias AccessChecker = @MainActor () -> Bool
    typealias AccessRequester = @MainActor () -> Bool
    typealias EventPoster = @MainActor (
        _ keyCode: CGKeyCode,
        _ keyDown: Bool,
        _ processIdentifier: pid_t
    ) -> Void

    private static let navigationKeyCodes: Set<UInt16> = [
        49,   // Space
        116,  // Page Up
        121,  // Page Down
        123,  // Left Arrow
        124,  // Right Arrow
        125,  // Down Arrow
        126,  // Up Arrow
    ]

    private let targetProvider: TargetProvider
    private let accessChecker: AccessChecker
    private let accessRequester: AccessRequester
    private let eventPoster: EventPoster

    private(set) var target: Target?

    init(
        targetProvider: @escaping TargetProvider = PresentationKeyForwarder.defaultTargetProvider,
        accessChecker: @escaping AccessChecker = { CGPreflightPostEventAccess() },
        accessRequester: @escaping AccessRequester = { CGRequestPostEventAccess() },
        eventPoster: @escaping EventPoster = PresentationKeyForwarder.defaultEventPoster
    ) {
        self.targetProvider = targetProvider
        self.accessChecker = accessChecker
        self.accessRequester = accessRequester
        self.eventPoster = eventPoster
    }

    var hasPostEventAccess: Bool {
        accessChecker()
    }

    func beginSession() {
        target = targetProvider()
    }

    func endSession() {
        target = nil
    }

    @discardableResult
    func requestPostEventAccess() -> Bool {
        hasPostEventAccess || accessRequester()
    }

    func forwardKeyDown(
        _ event: NSEvent,
        isEnabled: Bool,
        isTextEditing: Bool
    ) -> ForwardingResult {
        guard isEnabled, !isTextEditing else { return .notHandled }
        guard Self.navigationKeyCodes.contains(event.keyCode) else { return .notHandled }

        let conflictingModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(conflictingModifiers).isEmpty else {
            return .notHandled
        }

        // Consume repeats without forwarding them so one long press cannot skip many slides.
        guard !event.isARepeat else { return .consumed }
        guard let target else { return .targetUnavailable }
        guard hasPostEventAccess else { return .permissionRequired }

        let keyCode = CGKeyCode(event.keyCode)
        eventPoster(keyCode, true, target.processIdentifier)
        eventPoster(keyCode, false, target.processIdentifier)
        return .forwarded(target.applicationName)
    }

    private static func defaultTargetProvider() -> Target? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        return Target(
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? L10n.text("Presentation App")
        )
    }

    private static func defaultEventPoster(
        keyCode: CGKeyCode,
        keyDown: Bool,
        processIdentifier: pid_t
    ) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: keyDown
        )
        event?.postToPid(processIdentifier)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    var statusItem: NSStatusItem!
    private weak var currentToolStatusItem: NSMenuItem?
    private weak var currentDrawingModeStatusItem: NSMenuItem?
    private weak var currentOverlayModeStatusItem: NSMenuItem?
    var colorPopover: NSPopover?
    var lineWidthPopover: NSPopover?
    var currentColor: NSColor = .systemRed
    var hotkeyMonitor: Any?
    var overlayWindows: [NSScreen: OverlayWindow] = [:]
    var alwaysOnMode: Bool = false
    var aboutWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController!
    let userDefaults: UserDefaults
    let presentationKeyForwarder: PresentationKeyForwarder
    private(set) var isStatusMenuTracking = false
    private var didShowPresentationNavigationWarning = false

    // Cursor Highlight
    var cursorHighlightWindows: [NSScreen: CursorHighlightWindow] = [:]
    var globalMouseMoveMonitor: Any?
    var globalMouseClickMonitor: Any?
    var globalMouseUpMonitor: Any?
    var localMouseMoveMonitor: Any?
    var localMouseClickMonitor: Any?
    var localMouseUpMonitor: Any?
    var localFlagsChangedMonitor: Any?

    override init() {
        self.userDefaults = .standard
        self.presentationKeyForwarder = PresentationKeyForwarder()
        super.init()
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.presentationKeyForwarder = PresentationKeyForwarder()
        super.init()
    }

    init(userDefaults: UserDefaults, presentationKeyForwarder: PresentationKeyForwarder) {
        self.userDefaults = userDefaults
        self.presentationKeyForwarder = presentationKeyForwarder
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        updateDockIconVisibility()

        if let colorData = userDefaults.data(forKey: "SelectedColor"),
            let unarchivedColor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self, from: colorData)
        {
            currentColor = unarchivedColor
        }

        // Sync annotation color to cursor highlight manager
        CursorHighlightManager.shared.annotationColor = currentColor

        setupStatusBarItem()
        setupOverlayWindows()

        let persistedFadeMode =
            userDefaults.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        let persistedFadeDuration = userDefaults.annotationFadeDuration
        overlayWindows.values.forEach {
            $0.overlayView.fadeMode = persistedFadeMode
            $0.overlayView.fadeDuration = persistedFadeDuration
        }

        let shouldStartInAlwaysOnMode = userDefaults.bool(forKey: UserDefaults.alwaysOnModeKey)
        if shouldStartInAlwaysOnMode {
            DispatchQueue.main.async {
                self.toggleAlwaysOnMode()
            }
        }

        let persistedLineWidth = userDefaults.object(forKey: UserDefaults.lineWidthKey) as? Double ?? 3.0
        overlayWindows.values.forEach { $0.overlayView.currentLineWidth = CGFloat(persistedLineWidth) }

        let persistedTool = userDefaults.lastUsedTool
        overlayWindows.values.forEach { $0.overlayView.currentTool = persistedTool }
        updateCurrentToolMenuItem(to: persistedTool.displayName)

        let enableBoard = userDefaults.bool(forKey: UserDefaults.enableBoardKey)
        overlayWindows.values.forEach {
            $0.boardView.isHidden = !enableBoard
            $0.overlayView.updateAdaptColors(boardEnabled: enableBoard)
        }

        setupBoardObservers()

        let startUpdater = false

        updaterController = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        setupApplicationMenu()

        setupCursorHighlightWindows()
        setupGlobalMouseMonitors()
        setupCursorHighlightObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let monitors: [Any?] = [
            globalMouseMoveMonitor,
            globalMouseClickMonitor,
            globalMouseUpMonitor,
            localMouseMoveMonitor,
            localMouseClickMonitor,
            localMouseUpMonitor,
            localFlagsChangedMonitor
        ]
        monitors.compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }

        globalMouseMoveMonitor = nil
        globalMouseClickMonitor = nil
        globalMouseUpMonitor = nil
        localMouseMoveMonitor = nil
        localMouseClickMonitor = nil
        localMouseUpMonitor = nil
        localFlagsChangedMonitor = nil
    }

    @MainActor
    func updateDockIconVisibility() {
        guard NSApplication.shared.delegate != nil else { return }

        if userDefaults.bool(forKey: UserDefaults.hideDockIconKey) {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        visibleSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The settings window, if it is currently on screen.
    private var visibleSettingsWindow: NSWindow? {
        guard let window = SettingsWindowManager.shared.settingsWindow, window.isVisible else {
            return nil
        }
        return window
    }

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem.button != nil {
            updateStatusBarIcon(with: .gray)

            let menu = NSMenu()
            menu.delegate = self

            let colorItem = NSMenuItem(
                title: L10n.text("Color"),
                action: #selector(showColorPicker(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .colorPicker))
            colorItem.keyEquivalentModifierMask = []
            menu.addItem(colorItem)

            let lineWidthItem = NSMenuItem(
                title: L10n.text("Line Width"),
                action: #selector(showLineWidthPicker(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .lineWidthPicker))
            lineWidthItem.keyEquivalentModifierMask = []
            menu.addItem(lineWidthItem)

            menu.addItem(NSMenuItem.separator())

            let currentToolItem = NSMenuItem(
                title: L10n.format("Current Tool: %@", L10n.text("Pen")),
                action: nil,
                keyEquivalent: ""
            )
            currentToolItem.isEnabled = false
            menu.addItem(currentToolItem)
            currentToolStatusItem = currentToolItem

            let arrowModeItem = NSMenuItem(
                title: L10n.text("Arrow"),
                action: #selector(enableArrowMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .arrow))
            arrowModeItem.keyEquivalentModifierMask = []
            menu.addItem(arrowModeItem)

            let lineModeItem = NSMenuItem(
                title: L10n.text("Line"),
                action: #selector(enableLineMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .line))
            lineModeItem.keyEquivalentModifierMask = []
            menu.addItem(lineModeItem)

            let penModeItem = NSMenuItem(
                title: L10n.text("Pen"),
                action: #selector(enablePenMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .pen))
            penModeItem.keyEquivalentModifierMask = []
            menu.addItem(penModeItem)

            let highlighterModeItem = NSMenuItem(
                title: L10n.text("Highlighter"),
                action: #selector(enableHighlighterMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .highlighter))
            highlighterModeItem.keyEquivalentModifierMask = []
            menu.addItem(highlighterModeItem)

            let rectangleModeItem = NSMenuItem(
                title: L10n.text("Rectangle"),
                action: #selector(enableRectangleMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .rectangle))
            rectangleModeItem.keyEquivalentModifierMask = []
            menu.addItem(rectangleModeItem)

            let circleModeItem = NSMenuItem(
                title: L10n.text("Circle"),
                action: #selector(enableCircleMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .circle))
            circleModeItem.keyEquivalentModifierMask = []
            menu.addItem(circleModeItem)

            let counterModeItem = NSMenuItem(
                title: L10n.text("Counter"),
                action: #selector(enableCounterMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .counter))
            counterModeItem.keyEquivalentModifierMask = []
            menu.addItem(counterModeItem)

            let textModeItem = NSMenuItem(
                title: L10n.text("Text"),
                action: #selector(enableTextMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .text))
            textModeItem.keyEquivalentModifierMask = []
            menu.addItem(textModeItem)
            
            let selectModeItem = NSMenuItem(
                title: L10n.text("Select"),
                action: #selector(enableSelectMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .select))
            selectModeItem.keyEquivalentModifierMask = []
            menu.addItem(selectModeItem)

            let eraserModeItem = NSMenuItem(
                title: L10n.text("Eraser"),
                action: #selector(enableEraserMode(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .eraser))
            eraserModeItem.keyEquivalentModifierMask = []
            menu.addItem(eraserModeItem)

            menu.addItem(NSMenuItem.separator())

            let boardEnabled = userDefaults.bool(forKey: UserDefaults.enableBoardKey)
            let toggleBoardItem = NSMenuItem(
                title: boardToggleTitle(isEnabled: boardEnabled),
                action: #selector(toggleBoardVisibility(_:)),
                keyEquivalent: ShortcutManager.shared.getShortcut(for: .toggleBoard))
            toggleBoardItem.keyEquivalentModifierMask = []
            menu.addItem(toggleBoardItem)

            let clickEffectsEnabled = CursorHighlightManager.shared.clickEffectsEnabled
            let toggleClickEffectsItem = NSMenuItem(
                title: clickEffectsEnabled
                    ? L10n.text("Disable Pointer Effects")
                    : L10n.text("Enable Pointer Effects"),
                action: #selector(toggleClickEffects(_:)),
                keyEquivalent: "")
            toggleClickEffectsItem.setShortcut(for: .togglePresentationEffects)
            menu.addItem(toggleClickEffectsItem)

            let presentationNavigationEnabled = userDefaults.presentationNavigationEnabled
            let togglePresentationNavigationItem = NSMenuItem(
                title: presentationNavigationEnabled
                    ? L10n.text("Disable Presentation Navigation")
                    : L10n.text("Enable Presentation Navigation"),
                action: #selector(togglePresentationNavigation(_:)),
                keyEquivalent: ""
            )
            menu.addItem(togglePresentationNavigationItem)

            menu.addItem(NSMenuItem.separator())

            let persistedFadeMode =
                userDefaults.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
            let currentDrawingModeItem = NSMenuItem(
                title: persistedFadeMode
                    ? L10n.text("Drawing Mode: Fade")
                    : L10n.text("Drawing Mode: Persist"),
                action: nil,
                keyEquivalent: ""
            )
            currentDrawingModeItem.isEnabled = false
            menu.addItem(currentDrawingModeItem)
            currentDrawingModeStatusItem = currentDrawingModeItem

            let toggleDrawingModeItem = NSMenuItem(
                title: persistedFadeMode ? L10n.text("Persist") : L10n.text("Fade"),
                action: #selector(toggleFadeMode(_:)),
                keyEquivalent: ""
            )
            menu.addItem(toggleDrawingModeItem)

            menu.addItem(NSMenuItem.separator())
            
            let currentOverlayModeItem = NSMenuItem(
                title: alwaysOnMode
                    ? L10n.text("Overlay Mode: Always-On")
                    : L10n.text("Overlay Mode: Interactive"),
                action: nil,
                keyEquivalent: ""
            )
            currentOverlayModeItem.isEnabled = false
            menu.addItem(currentOverlayModeItem)
            currentOverlayModeStatusItem = currentOverlayModeItem
            
            let toggleAlwaysOnModeItem = NSMenuItem(
                title: alwaysOnMode
                    ? L10n.text("Exit Always-On Mode")
                    : L10n.text("Always-On Mode"),
                action: #selector(toggleAlwaysOnMode),
                keyEquivalent: ""
            )
            menu.addItem(toggleAlwaysOnModeItem)

            menu.addItem(NSMenuItem.separator())

            let clearAllItem = NSMenuItem(
                title: L10n.text("Clear All"),
                action: #selector(clearAllAnnotations),
                keyEquivalent: "\u{8}"
            )
            clearAllItem.keyEquivalentModifierMask = [.option]
            menu.addItem(clearAllItem)

            let undoItem = NSMenuItem(
                title: L10n.text("Undo"),
                action: #selector(undo),
                keyEquivalent: "z")
            menu.addItem(undoItem)

            let redoItem = NSMenuItem(
                title: L10n.text("Redo"),
                action: #selector(redo),
                keyEquivalent: "Z")
            menu.addItem(redoItem)

            menu.addItem(NSMenuItem.separator())

            let settingsItem = NSMenuItem(
                title: L10n.text("Settings..."),
                action: #selector(showSettings),
                keyEquivalent: ",")
            settingsItem.keyEquivalentModifierMask = [.command]
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())

            menu.addItem(
                NSMenuItem(
                    title: L10n.text("Close"),
                    action: #selector(closeOverlay),
                    keyEquivalent: "w"))

            menu.addItem(
                NSMenuItem(
                    title: L10n.text("Quit"), action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"))

            statusItem.menu = menu
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }

        KeyboardShortcuts.disable(
            .toggleOverlay,
            .togglePresentationEffects,
            .toggleAlwaysOnMode
        )
        isStatusMenuTracking = true
        let manager = CursorHighlightManager.shared
        manager.isMouseDown = false
        manager.releaseAnimation = nil
        manager.showSystemCursor()

        cursorHighlightWindows.values.forEach { window in
            window.stopAnimationLoop()
            window.orderOut(nil)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }

        KeyboardShortcuts.enable(
            .toggleOverlay,
            .togglePresentationEffects,
            .toggleAlwaysOnMode
        )
        isStatusMenuTracking = false
        let manager = CursorHighlightManager.shared
        manager.cursorPosition = NSEvent.mouseLocation
        manager.updateCursorVisibility()
        cursorHighlightWindows.values.forEach { $0.updateVisibility() }
    }

    @objc func screenParametersChanged() {
        // Remove windows for screens that no longer exist
        overlayWindows = overlayWindows.filter { screen, _ in
            NSScreen.screens.contains(screen)
        }

        // Add new overlays for newly added screens
        for screen in NSScreen.screens {
            if overlayWindows[screen] == nil {
                let overlayWindow = OverlayWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                overlayWindow.currentColor = currentColor

                let savedLineWidth = userDefaults.object(forKey: UserDefaults.lineWidthKey) as? Double ?? 3.0
                overlayWindow.overlayView.currentLineWidth = CGFloat(savedLineWidth)
                overlayWindow.overlayView.currentTool = userDefaults.lastUsedTool
                overlayWindow.overlayView.fadeMode =
                    userDefaults.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
                overlayWindow.overlayView.fadeDuration = userDefaults.annotationFadeDuration

                overlayWindows[screen] = overlayWindow
            }
        }

        updateCursorHighlightWindowsForScreenChange()
    }

    func getCurrentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    func setupOverlayWindows() {
        for screen in NSScreen.screens {
            // Convert screen coordinates to global coordinates
            let globalFrame = screen.frame

            let overlayWindow = OverlayWindow(
                contentRect: globalFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            overlayWindow.setFrameOrigin(globalFrame.origin)
            overlayWindow.currentColor = currentColor
            overlayWindow.overlayView.fadeDuration = userDefaults.annotationFadeDuration
            overlayWindows[screen] = overlayWindow
        }
    }

    @objc func showColorPicker(_ sender: Any?) {
        if colorPopover == nil {
            colorPopover = NSPopover()
            colorPopover?.contentViewController = ColorPickerViewController(userDefaults: userDefaults)
            colorPopover?.behavior = .transient
            colorPopover?.delegate = self
        }

        if let button = statusItem.button {
            colorPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            if let popoverWindow = colorPopover?.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
            }
        }
    }

    @objc func showLineWidthPicker(_ sender: Any?) {
        if lineWidthPopover == nil {
            lineWidthPopover = NSPopover()
            lineWidthPopover?.contentViewController = LineWidthPickerViewController(userDefaults: userDefaults)
            lineWidthPopover?.behavior = .transient
            lineWidthPopover?.delegate = self
        }

        if let button = statusItem.button {
            lineWidthPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            if let popoverWindow = lineWidthPopover?.contentViewController?.view.window {
                popoverWindow.level = .popUpMenu
            }
        }
    }

    func popoverWillClose(_ notification: Notification) {
        if let popover = notification.object as? NSPopover {
            if popover == colorPopover {
                colorPopover = nil
            } else if popover == lineWidthPopover {
                lineWidthPopover = nil
            }
        }
    }

    @objc func toggleOverlay() {
        // Always-on mode is incompatible with interactive overlay
        if alwaysOnMode {
            toggleAlwaysOnMode()
        }

        guard let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen]
        else {
            return
        }

        if overlayWindow.isVisible {
            if let activeField = overlayWindow.overlayView.activeTextField {
                overlayWindow.overlayView.finalizeTextAnnotation(activeField)
            }
            updateStatusBarIcon(with: .gray)
            overlayWindow.orderOut(nil)
            endPresentationNavigationSessionIfNeeded()
            CursorHighlightManager.shared.overlayVisibilityChanged()
        } else {
            configureWindowForNormalMode(overlayWindow)

            if userDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
                overlayWindow.overlayView.clearAll()
            }

            updateStatusBarIcon(with: currentColor)
            let screenFrame = currentScreen.frame
            overlayWindow.setFrame(screenFrame, display: true)
            beginPresentationNavigationSession(for: overlayWindow)
            overlayWindow.makeKeyAndOrderFront(nil)
            CursorHighlightManager.shared.annotationColor = currentColor
            CursorHighlightManager.shared.overlayVisibilityChanged()
            applyConfiguredDefaultTool()
        }
    }

    @objc func toggleAlwaysOnMode() {
        alwaysOnMode.toggle()
        presentationKeyForwarder.endSession()
        didShowPresentationNavigationWarning = false

        overlayWindows.values.forEach { overlayWindow in
            if let activeField = overlayWindow.overlayView.activeTextField {
                overlayWindow.overlayView.finalizeTextAnnotation(activeField)
            }
            if alwaysOnMode {
                configureWindowForAlwaysOnMode(overlayWindow)
            } else {
                configureWindowForNormalMode(overlayWindow)
                overlayWindow.orderOut(nil)
            }
        }

        let iconColor = alwaysOnMode
            ? currentColor.withAlphaComponent(0.7)
            : .gray
        updateStatusBarIcon(with: iconColor)

        userDefaults.set(alwaysOnMode, forKey: UserDefaults.alwaysOnModeKey)
        updateAlwaysOnMenuItems()
        CursorHighlightManager.shared.overlayVisibilityChanged()
    }

    @objc func closeOverlay() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            if let activeField = overlayWindow.overlayView.activeTextField {
                overlayWindow.overlayView.finalizeTextAnnotation(activeField)
            }
            updateStatusBarIcon(with: .gray)
            overlayWindow.orderOut(nil)
            endPresentationNavigationSessionIfNeeded()
            CursorHighlightManager.shared.overlayVisibilityChanged()
        }
    }

    @objc func closeOverlayAndEnableAlwaysOn() {
        if !alwaysOnMode {
            toggleAlwaysOnMode()
        }
    }

    @objc func showOverlay() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            !overlayWindow.isVisible
        {
            configureWindowForNormalMode(overlayWindow)
            updateStatusBarIcon(with: currentColor)
            let screenFrame = currentScreen.frame
            overlayWindow.setFrame(screenFrame, display: true)
            beginPresentationNavigationSession(for: overlayWindow)
            overlayWindow.makeKeyAndOrderFront(nil)
            CursorHighlightManager.shared.annotationColor = currentColor
            CursorHighlightManager.shared.overlayVisibilityChanged()
        }
    }

    func switchTool(to tool: ToolType, persist: Bool = true) {
        if alwaysOnMode {
            toggleAlwaysOnMode()
        }

        if persist {
            userDefaults.lastUsedTool = tool
        }

        overlayWindows.values.forEach { window in
            if window.overlayView.currentTool == .select && tool != .select {
                window.overlayView.selectedObjects.removeAll()
                window.overlayView.needsDisplay = true
            }
            // Save current tool as previous when switching TO text mode
            if tool == .text && window.overlayView.currentTool != .text {
                window.overlayView.previousTool = window.overlayView.currentTool
            }
            window.overlayView.currentTool = tool
            window.showToolFeedback(tool)
            window.invalidateCursorRects(for: window.overlayView)
            window.overlayView.updateCursor()
        }
        updateCurrentToolMenuItem(to: tool.displayName)
        showOverlay()
    }

    /// Applies the configured default tool when the overlay activates. Does nothing when the
    /// setting is "Last used", leaving whatever tool is already current in place, or when
    /// every window is already on the configured tool (avoids showing tool feedback on
    /// every activation). Applying the default is not an explicit tool selection, so it does
    /// not overwrite the persisted last-used tool.
    func applyConfiguredDefaultTool() {
        guard case .tool(let tool) = userDefaults.defaultToolOption else { return }
        guard overlayWindows.values.contains(where: { $0.overlayView.currentTool != tool }) else { return }
        switchTool(to: tool, persist: false)
    }

    @objc func enableArrowMode(_ sender: NSMenuItem) {
        switchTool(to: .arrow)
    }

    @objc func enableLineMode(_ sender: NSMenuItem) {
        switchTool(to: .line)
    }

    @objc func enablePenMode(_ sender: NSMenuItem) {
        switchTool(to: .pen)
    }

    @objc func enableHighlighterMode(_ sender: NSMenuItem) {
        switchTool(to: .highlighter)
    }

    @objc func enableRectangleMode(_ sender: NSMenuItem) {
        switchTool(to: .rectangle)
    }

    @objc func enableCircleMode(_ sender: NSMenuItem) {
        switchTool(to: .circle)
    }

    @objc func enableCounterMode(_ sender: NSMenuItem) {
        switchTool(to: .counter)
    }

    @objc func enableTextMode(_ sender: NSMenuItem) {
        switchTool(to: .text)
    }

    @objc func enableSelectMode(_ sender: NSMenuItem) {
        switchTool(to: .select)
    }

    @objc func enableEraserMode(_ sender: NSMenuItem) {
        switchTool(to: .eraser)
    }

    @objc func toggleBoardVisibility(_ sender: Any?) {
        BoardManager.shared.toggle()
        updateBoardMenuItems()
    }

    private func boardToggleTitle(isEnabled: Bool) -> String {
        let isBlackboard = BoardManager.shared.currentBoardType == .blackboard
        switch (isEnabled, isBlackboard) {
        case (true, true): return L10n.text("Hide Blackboard")
        case (true, false): return L10n.text("Hide Whiteboard")
        case (false, true): return L10n.text("Show Blackboard")
        case (false, false): return L10n.text("Show Whiteboard")
        }
    }

    func updateBoardMenuItems() {
        guard let menu = statusItem.menu else { return }

        let boardEnabled = BoardManager.shared.isEnabled

        let toggleBoardItem = menu.items.first { $0.action == #selector(toggleBoardVisibility(_:)) }

        if let item = toggleBoardItem {
            item.title = boardToggleTitle(isEnabled: boardEnabled)
        }
    }

    @objc func toggleClickEffects(_ sender: Any?) {
        let newState = !CursorHighlightManager.shared.clickEffectsEnabled
        CursorHighlightManager.shared.clickEffectsEnabled = newState
        CursorHighlightManager.shared.cursorHighlightEnabled = newState
        updateClickEffectsMenuItems()

        let text = newState
            ? L10n.text("Pointer Effects On")
            : L10n.text("Pointer Effects Off")
        let icon = newState ? "👆" : "🚫"
        for (_, window) in overlayWindows where window.isVisible {
            window.showToggleFeedback(text, icon: icon)
        }
    }

    func updateClickEffectsMenuItems() {
        guard let menu = statusItem.menu else { return }
        if let item = menu.items.first(where: { $0.action == #selector(toggleClickEffects(_:)) }) {
            let isEnabled = CursorHighlightManager.shared.clickEffectsEnabled
            item.title = isEnabled
                ? L10n.text("Disable Pointer Effects")
                : L10n.text("Enable Pointer Effects")
        }
    }

    @objc func togglePresentationNavigation(_ sender: Any?) {
        setPresentationNavigationEnabled(!userDefaults.presentationNavigationEnabled)
    }

    func setPresentationNavigationEnabled(_ isEnabled: Bool) {
        userDefaults.presentationNavigationEnabled = isEnabled
        updatePresentationNavigationMenuItem()

        if isEnabled, !presentationKeyForwarder.hasPostEventAccess {
            _ = requestPresentationNavigationAccess()
        }

        let text = isEnabled
            ? L10n.text("Presentation Navigation On")
            : L10n.text("Presentation Navigation Off")
        let icon = isEnabled ? "⌨️" : "🚫"
        for (_, window) in overlayWindows where window.isVisible {
            window.showToggleFeedback(text, icon: icon)
        }
    }

    @discardableResult
    func requestPresentationNavigationAccess() -> Bool {
        userDefaults.set(true, forKey: UserDefaults.presentationPostEventAccessRequestedKey)
        let isGranted = presentationKeyForwarder.requestPostEventAccess()
        didShowPresentationNavigationWarning = false
        return isGranted
    }

    func updatePresentationNavigationMenuItem() {
        guard let menu = statusItem.menu else { return }
        if let item = menu.items.first(where: {
            $0.action == #selector(togglePresentationNavigation(_:))
        }) {
            item.title = userDefaults.presentationNavigationEnabled
                ? L10n.text("Disable Presentation Navigation")
                : L10n.text("Enable Presentation Navigation")
        }
    }

    /// Handles only the small, unmodified presentation-navigation allowlist. Returning true
    /// means the overlay should consume the event, whether it was forwarded or a useful
    /// permission/target warning was shown.
    func forwardPresentationNavigationKey(
        _ event: NSEvent,
        isTextEditing: Bool
    ) -> Bool {
        let result = presentationKeyForwarder.forwardKeyDown(
            event,
            isEnabled: userDefaults.presentationNavigationEnabled,
            isTextEditing: isTextEditing
        )

        switch result {
        case .notHandled:
            return false
        case .consumed, .forwarded:
            return true
        case .permissionRequired:
            showPresentationNavigationWarning(
                L10n.text("Presentation key access required"),
                icon: "⚠️"
            )
            return true
        case .targetUnavailable:
            showPresentationNavigationWarning(
                L10n.text("Presentation target unavailable"),
                icon: "⚠️"
            )
            return true
        }
    }

    private func beginPresentationNavigationSession(for overlayWindow: OverlayWindow) {
        presentationKeyForwarder.beginSession()
        didShowPresentationNavigationWarning = false

        guard userDefaults.presentationNavigationEnabled else { return }

        if !presentationKeyForwarder.hasPostEventAccess,
            !userDefaults.bool(forKey: UserDefaults.presentationPostEventAccessRequestedKey)
        {
            _ = requestPresentationNavigationAccess()
        }

        if !presentationKeyForwarder.hasPostEventAccess {
            overlayWindow.showToggleFeedback(
                L10n.text("Presentation key access required"),
                icon: "⚠️"
            )
            didShowPresentationNavigationWarning = true
        } else if let target = presentationKeyForwarder.target {
            overlayWindow.showToggleFeedback(
                L10n.format("Presentation keys connected: %@", target.applicationName),
                icon: "⌨️"
            )
        } else {
            overlayWindow.showToggleFeedback(
                L10n.text("Presentation target unavailable"),
                icon: "⚠️"
            )
            didShowPresentationNavigationWarning = true
        }
    }

    private func endPresentationNavigationSessionIfNeeded() {
        let hasInteractiveOverlay = overlayWindows.values.contains {
            $0.isVisible && !$0.ignoresMouseEvents
        }
        if !hasInteractiveOverlay {
            presentationKeyForwarder.endSession()
            didShowPresentationNavigationWarning = false
        }
    }

    private func showPresentationNavigationWarning(_ text: String, icon: String) {
        guard !didShowPresentationNavigationWarning else { return }
        didShowPresentationNavigationWarning = true
        for (_, window) in overlayWindows where window.isVisible {
            window.showToggleFeedback(text, icon: icon)
        }
    }

    func updateAlwaysOnMenuItems() {
        guard let menu = statusItem.menu else { return }

        if let item = currentOverlayModeStatusItem {
            item.title = alwaysOnMode
                ? L10n.text("Overlay Mode: Always-On")
                : L10n.text("Overlay Mode: Interactive")
        }

        let toggleAlwaysOnModeItem = menu.items.first { $0.action == #selector(toggleAlwaysOnMode) }
        if let item = toggleAlwaysOnModeItem {
            item.title = alwaysOnMode
                ? L10n.text("Exit Always-On Mode")
                : L10n.text("Always-On Mode")
        }
    }

    func updateCurrentToolMenuItem(to toolName: String) {
        currentToolStatusItem?.title = L10n.format("Current Tool: %@", toolName)
    }
    
    private func configureWindowForNormalMode(_ overlayWindow: OverlayWindow) {
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.overlayView.isReadOnlyMode = false

        let persistedFadeMode = userDefaults.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        overlayWindow.overlayView.fadeMode = persistedFadeMode
        overlayWindow.overlayView.fadeDuration = userDefaults.annotationFadeDuration
    }

    private func configureWindowForAlwaysOnMode(_ overlayWindow: OverlayWindow) {
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.overlayView.fadeMode = false
        overlayWindow.overlayView.isReadOnlyMode = true

        let screenFrame = overlayWindow.screen?.frame ?? NSScreen.main?.frame ?? .zero
        overlayWindow.setFrame(screenFrame, display: true)
        overlayWindow.orderFront(nil)
        overlayWindow.stopFadeLoop()
    }
    
    private func updateFadeModeMenuItems(isFadeMode: Bool) {
        guard let menu = statusItem.menu else { return }

        let toggleDrawingModeItem = menu.items.first { 
            $0.action == #selector(toggleFadeMode(_:)) 
        }

        currentDrawingModeStatusItem?.title = isFadeMode
            ? L10n.text("Drawing Mode: Fade")
            : L10n.text("Drawing Mode: Persist")

        toggleDrawingModeItem?.title = isFadeMode
            ? L10n.text("Persist")
            : L10n.text("Fade")
    }

    func setupBoardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boardStateChanged),
            name: .boardStateChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boardAppearanceChanged),
            name: .boardAppearanceChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: .shortcutsDidChange,
            object: nil
        )
    }

    @objc func boardStateChanged() {
        updateBoardMenuItems()
    }

    @objc func boardAppearanceChanged() {
        updateBoardMenuItems()
    }

    @objc func shortcutsDidChange() {
        refreshMenuKeyEquivalents()
    }

    func refreshMenuKeyEquivalents() {
        guard let menu = statusItem.menu else { return }

        for item in menu.items {
            switch item.action {
            case #selector(showColorPicker(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .colorPicker)
            case #selector(showLineWidthPicker(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .lineWidthPicker)
            case #selector(enableArrowMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .arrow)
            case #selector(enableLineMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .line)
            case #selector(enablePenMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .pen)
            case #selector(enableHighlighterMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .highlighter)
            case #selector(enableRectangleMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .rectangle)
            case #selector(enableCircleMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .circle)
            case #selector(enableCounterMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .counter)
            case #selector(enableTextMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .text)
            case #selector(enableSelectMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .select)
            case #selector(enableEraserMode(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .eraser)
            case #selector(toggleBoardVisibility(_:)):
                item.keyEquivalent = ShortcutManager.shared.getShortcut(for: .toggleBoard)
            default:
                break
            }
        }
    }

    @objc func undo() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            overlayWindow.overlayView.undo()
        }
    }

    @objc func redo() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            overlayWindow.overlayView.redo()
        }
    }

    @objc func clearAllAnnotations() {
        if let currentScreen = getCurrentScreen(),
            let overlayWindow = overlayWindows[currentScreen],
            overlayWindow.isVisible
        {
            overlayWindow.overlayView.clearAll()
        }
    }

    @objc func toggleFadeMode(_ sender: Any?) {
        let isCurrentlyFadeMode = overlayWindows.values.first?.overlayView.fadeMode ?? true
        let newFadeMode = !isCurrentlyFadeMode
        setFadeMode(newFadeMode)

        let text = newFadeMode ? L10n.text("Fade Mode") : L10n.text("Persist Mode")
        let icon = newFadeMode ? "⏳" : "📌"
        for (_, window) in overlayWindows where window.isVisible {
            window.showToggleFeedback(text, icon: icon)
        }
    }

    func setFadeMode(_ isFadeMode: Bool) {
        userDefaults.set(isFadeMode, forKey: UserDefaults.fadeModeKey)

        for window in overlayWindows.values {
            window.overlayView.fadeMode = isFadeMode
            if isFadeMode, window.overlayView.isAnythingFading() {
                window.startFadeLoop()
            } else if !isFadeMode {
                window.stopFadeLoop()
                window.overlayView.needsDisplay = true
            }
        }

        updateFadeModeMenuItems(isFadeMode: isFadeMode)
    }

    func updateFadeDuration(_ duration: CFTimeInterval) {
        let clampedDuration = min(
            max(duration, annotationFadeDurationRange.lowerBound),
            annotationFadeDurationRange.upperBound
        )
        userDefaults.annotationFadeDuration = clampedDuration

        for window in overlayWindows.values {
            window.overlayView.fadeDuration = clampedDuration
            if window.overlayView.fadeMode, window.overlayView.isAnythingFading() {
                window.startFadeLoop()
            }
            window.overlayView.needsDisplay = true
        }
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowManager.shared.show()
    }

    /// Updates the status bar icon by layering a colored circle with a pencil.
    /// - Parameter color: The color to apply to the circle.
    func updateStatusBarIcon(with color: NSColor) {
        let pencilSymbolName = "pencil"
        let iconSize = NSSize(width: 18, height: 18)

        let compositeImage = NSImage(size: iconSize)
        compositeImage.lockFocus()

        // Draw the circle outline
        let circleFrame = NSRect(origin: NSPoint(x: 1, y: 1), size: NSSize(width: 16, height: 16))  // Slight inset for stroke
        let circlePath = NSBezierPath(ovalIn: circleFrame)
        color.setStroke()
        circlePath.lineWidth = 1.5
        circlePath.stroke()

        // Load the pencil image
        guard
            let pencilImage = NSImage(
                systemSymbolName: pencilSymbolName, accessibilityDescription: "Pencil")
        else {
            print("Failed to load system symbol: \(pencilSymbolName)")
            return
        }

        let coloredPencil = pencilImage.copy() as! NSImage
        coloredPencil.lockFocus()
        NSColor.white.set()
        let pencilBounds = NSRect(origin: .zero, size: pencilImage.size)
        pencilBounds.fill(using: .sourceIn)  // Tint the image white
        coloredPencil.unlockFocus()

        // Center and draw the white pencil icon
        let pencilSize = NSSize(width: 11, height: 11)
        let pencilOrigin = NSPoint(
            x: (iconSize.width - pencilSize.width) / 2, y: (iconSize.height - pencilSize.height) / 2
        )
        coloredPencil.draw(
            in: NSRect(origin: pencilOrigin, size: pencilSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0)

        compositeImage.unlockFocus()
        compositeImage.isTemplate = false

        // Set the composite image to the status bar button
        statusItem.button?.image = compositeImage
    }
    
    func setupApplicationMenu() {
        guard let mainMenu = NSApp.mainMenu,
              let appMenuItem = mainMenu.items.first,
              let appMenu = appMenuItem.submenu else {
            return
        }

        for item in appMenu.items {
            if item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) {
                item.target = self
                item.action = #selector(showAbout)
                break
            }
        }
    }
    
    @objc func showAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView(updaterController: updaterController)
            let hostingController = NSHostingController(rootView: aboutView)
            
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutWindow?.contentViewController = hostingController
            aboutWindow?.title = L10n.text("About Annotate")
            aboutWindow?.isReleasedWhenClosed = false
            aboutWindow?.delegate = self
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async {
            self.aboutWindow?.center()
        }

        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - Cursor Highlighting

    private func createCursorHighlightWindow(for screen: NSScreen) -> CursorHighlightWindow {
        let window = CursorHighlightWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(screen.frame.origin)
        return window
    }

    func setupCursorHighlightWindows() {
        for screen in NSScreen.screens {
            let window = createCursorHighlightWindow(for: screen)
            cursorHighlightWindows[screen] = window
            window.updateVisibility()
        }
    }

    func setupGlobalMouseMonitors() {
        // Global monitors - receive events when app is NOT frontmost
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleGlobalMouseMove(event)
        }

        globalMouseClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleGlobalMouseDown(event)
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.handleGlobalMouseUp(event)
        }

        // Local monitors - receive events when app IS frontmost (e.g., Settings window open)
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.handleGlobalMouseMove(event)
            return event
        }

        localMouseClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleGlobalMouseDown(event)
            return event
        }

        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.handleGlobalMouseUp(event)
            return event
        }

        // Modifier keys from hotkeys can trigger cursor resets
        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged]
        ) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func handleFlagsChanged(_ event: NSEvent) {
        guard !isStatusMenuTracking else { return }
        CursorHighlightManager.shared.updateCursorVisibility()
    }

    func setupCursorHighlightObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cursorHighlightStateChanged),
            name: .cursorHighlightStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cursorHighlightNeedsUpdate),
            name: .cursorHighlightNeedsUpdate,
            object: nil
        )
    }

    @objc func cursorHighlightNeedsUpdate() {
        triggerCursorHighlightUpdate()
    }

    @objc func cursorHighlightStateChanged() {
        updateAllCursorHighlightWindows()
        CursorHighlightManager.shared.updateCursorVisibility()
        overlayWindows.values.forEach { window in
            window.overlayView.updateCursor()
            window.overlayView.window?.invalidateCursorRects(for: window.overlayView)
        }
    }

    /// Called from OverlayWindow to trigger cursor highlight updates for local mouse events
    func triggerCursorHighlightUpdate() {
        cursorHighlightWindows.values.forEach { $0.highlightView.updateHoldRingPosition() }

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.startAnimationLoop()
        }
    }

    func handleGlobalMouseMove(_ event: NSEvent) {
        guard !isStatusMenuTracking else { return }

        let manager = CursorHighlightManager.shared
        manager.cursorPosition = NSEvent.mouseLocation
        manager.updateCursorVisibility()

        let shouldUpdateSpotlight = manager.shouldShowCursorHighlight
        let shouldUpdateHoldRing = manager.isActive && manager.isMouseDown

        guard shouldUpdateSpotlight || shouldUpdateHoldRing else { return }

        cursorHighlightWindows.values.forEach { window in
            if shouldUpdateSpotlight { window.highlightView.updateSpotlightPosition() }
            if shouldUpdateHoldRing { window.highlightView.updateHoldRingPosition() }
        }

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.startAnimationLoop()
        }
    }

    func handleGlobalMouseDown(_ event: NSEvent) {
        guard !isStatusMenuTracking else { return }

        let manager = CursorHighlightManager.shared
        guard manager.isActive else { return }

        manager.isMouseDown = true
        manager.mouseDownTime = CACurrentMediaTime()
        manager.cursorPosition = NSEvent.mouseLocation

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.highlightView.updateHoldRingPosition()
            window.startAnimationLoop()
        }
    }

    func handleGlobalMouseUp(_ event: NSEvent) {
        guard !isStatusMenuTracking else { return }

        let manager = CursorHighlightManager.shared

        guard manager.isActive else {
            manager.isMouseDown = false
            return
        }

        manager.startReleaseAnimation()
        manager.isMouseDown = false

        cursorHighlightWindows.values.forEach { $0.highlightView.updateHoldRingPosition() }

        if let currentScreen = getCurrentScreen(),
           let window = cursorHighlightWindows[currentScreen]
        {
            window.startAnimationLoop()
        }
    }

    func updateAllCursorHighlightWindows() {
        cursorHighlightWindows.values.forEach { $0.updateVisibility() }
    }

    func updateCursorHighlightWindowsForScreenChange() {
        // Remove windows for disconnected screens
        cursorHighlightWindows = cursorHighlightWindows.filter { screen, window in
            let exists = NSScreen.screens.contains(screen)
            if !exists {
                window.stopAnimationLoop()
                window.orderOut(nil)
            }
            return exists
        }

        // Add windows for newly connected screens
        for screen in NSScreen.screens where cursorHighlightWindows[screen] == nil {
            let window = createCursorHighlightWindow(for: screen)
            cursorHighlightWindows[screen] = window
            window.updateVisibility()
        }
    }
}
