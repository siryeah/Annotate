import Foundation
import XCTest

@testable import Annotate

@MainActor
final class AppDelegateTests: XCTestCase, Sendable {
    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!
    var forwardedPresentationEvents: [(CGKeyCode, Bool, pid_t)] = []

    nonisolated override func setUp() {
        super.setUp()

        MainActor.assumeIsolated {
            testDefaults = TestUserDefaults.create()
            BoardManager.shared = BoardManager(userDefaults: testDefaults)
            ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)
            forwardedPresentationEvents = []

            let presentationForwarder = PresentationKeyForwarder(
                targetProvider: {
                    PresentationKeyForwarder.Target(
                        processIdentifier: 4242,
                        applicationName: "Test Presentation"
                    )
                },
                accessChecker: { true },
                accessRequester: { true },
                eventPoster: { [weak self] keyCode, keyDown, processIdentifier in
                    self?.forwardedPresentationEvents.append(
                        (keyCode, keyDown, processIdentifier)
                    )
                }
            )

            appDelegate = AppDelegate(
                userDefaults: testDefaults,
                presentationKeyForwarder: presentationForwarder
            )
            appDelegate.applicationDidFinishLaunching(
                Notification(name: NSApplication.didFinishLaunchingNotification))
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            appDelegate = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(appDelegate.statusItem)
        XCTAssertNotNil(appDelegate.statusItem.menu)
        XCTAssertEqual(appDelegate.currentColor, .systemRed)
        XCTAssertNotNil(AppDelegate.shared)
    }

    func testStatusBarMenu() {
        guard let menu = appDelegate.statusItem.menu else {
            XCTFail("Status bar menu not initialized")
            return
        }

        // Verify menu structure
        XCTAssertGreaterThan(menu.items.count, 0)

        // Test color picker item
        let colorItem = menu.items.first { $0.action == #selector(AppDelegate.showColorPicker(_:)) }
        XCTAssertNotNil(colorItem)

        // Test tool items
        let penItem = menu.items.first { $0.action == #selector(AppDelegate.enablePenMode(_:)) }
        XCTAssertNotNil(penItem)

        let presentationItem = menu.items.first {
            $0.action == #selector(AppDelegate.togglePresentationNavigation(_:))
        }
        XCTAssertEqual(
            presentationItem?.title,
            L10n.text("Disable Presentation Navigation")
        )

        let fadeItem = menu.items.first {
            $0.action == #selector(AppDelegate.toggleFadeMode(_:))
        }
        XCTAssertEqual(fadeItem?.keyEquivalent, "")
    }

    // MARK: - Presentation Navigation Tests

    func testPresentationNavigationDefaultsToEnabledAndPersists() {
        XCTAssertTrue(testDefaults.presentationNavigationEnabled)

        appDelegate.setPresentationNavigationEnabled(false)
        XCTAssertFalse(testDefaults.presentationNavigationEnabled)

        let menuItem = appDelegate.statusItem.menu?.items.first {
            $0.action == #selector(AppDelegate.togglePresentationNavigation(_:))
        }
        XCTAssertEqual(menuItem?.title, L10n.text("Enable Presentation Navigation"))
    }

    func testPresentationForwarderPostsKeyDownAndKeyUpForAllowedKey() throws {
        let forwarder = appDelegate.presentationKeyForwarder
        forwarder.beginSession()
        let event = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 49))

        let result = forwarder.forwardKeyDown(
            event,
            isEnabled: true,
            isTextEditing: false
        )

        XCTAssertEqual(result, .forwarded("Test Presentation"))
        XCTAssertEqual(forwardedPresentationEvents.count, 2)
        XCTAssertEqual(forwardedPresentationEvents[0].0, 49)
        XCTAssertTrue(forwardedPresentationEvents[0].1)
        XCTAssertEqual(forwardedPresentationEvents[0].2, 4242)
        XCTAssertFalse(forwardedPresentationEvents[1].1)
    }

    func testOverlaySpaceForwardsWithoutChangingFadeMode() throws {
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows.values.first)
        overlayWindow.overlayView.fadeMode = true
        appDelegate.presentationKeyForwarder.beginSession()
        let event = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 49))

        overlayWindow.keyDown(with: event)

        XCTAssertTrue(overlayWindow.overlayView.fadeMode)
        XCTAssertEqual(forwardedPresentationEvents.count, 2)
    }

    func testOverlayDoesNotForwardArrowWhileEditingText() throws {
        let overlayWindow = try XCTUnwrap(appDelegate.overlayWindows.values.first)
        let textField = NSTextField(frame: .zero)
        overlayWindow.overlayView.activeTextField = textField
        appDelegate.presentationKeyForwarder.beginSession()
        let event = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 124))

        overlayWindow.keyDown(with: event)

        XCTAssertTrue(forwardedPresentationEvents.isEmpty)
        overlayWindow.overlayView.activeTextField = nil
    }

    func testPresentationForwarderSupportsArrowAndPageKeys() throws {
        let forwarder = appDelegate.presentationKeyForwarder
        forwarder.beginSession()

        for keyCode: UInt16 in [116, 121, 123, 124, 125, 126] {
            let event = try XCTUnwrap(
                TestEvents.createKeyEvent(type: .keyDown, keyCode: keyCode)
            )
            XCTAssertEqual(
                forwarder.forwardKeyDown(
                    event,
                    isEnabled: true,
                    isTextEditing: false
                ),
                .forwarded("Test Presentation")
            )
        }

        XCTAssertEqual(forwardedPresentationEvents.count, 12)
    }

    func testPresentationForwarderDoesNotInterceptTextEditing() throws {
        let forwarder = appDelegate.presentationKeyForwarder
        forwarder.beginSession()

        for keyCode: UInt16 in [49, 123, 124, 125, 126] {
            let event = try XCTUnwrap(
                TestEvents.createKeyEvent(type: .keyDown, keyCode: keyCode)
            )
            XCTAssertEqual(
                forwarder.forwardKeyDown(
                    event,
                    isEnabled: true,
                    isTextEditing: true
                ),
                .notHandled
            )
        }

        XCTAssertTrue(forwardedPresentationEvents.isEmpty)
    }

    func testPresentationForwarderRejectsEscapeLettersAndModifiedKeys() throws {
        let forwarder = appDelegate.presentationKeyForwarder
        forwarder.beginSession()
        let events = [
            TestEvents.createKeyEvent(type: .keyDown, keyCode: 53),
            TestEvents.createKeyEvent(type: .keyDown, keyCode: 0, characters: "a"),
            TestEvents.createKeyEvent(type: .keyDown, keyCode: 49, modifierFlags: .command),
            TestEvents.createKeyEvent(type: .keyDown, keyCode: 124, modifierFlags: .shift),
        ]

        for optionalEvent in events {
            let event = try XCTUnwrap(optionalEvent)
            XCTAssertEqual(
                forwarder.forwardKeyDown(
                    event,
                    isEnabled: true,
                    isTextEditing: false
                ),
                .notHandled
            )
        }

        XCTAssertTrue(forwardedPresentationEvents.isEmpty)
    }

    func testPresentationForwarderConsumesRepeatWithoutPosting() throws {
        let forwarder = appDelegate.presentationKeyForwarder
        forwarder.beginSession()
        let event = try XCTUnwrap(
            TestEvents.createKeyEvent(type: .keyDown, keyCode: 124, isARepeat: true)
        )

        XCTAssertEqual(
            forwarder.forwardKeyDown(event, isEnabled: true, isTextEditing: false),
            .consumed
        )
        XCTAssertTrue(forwardedPresentationEvents.isEmpty)
    }

    func testPresentationForwarderReportsPermissionAndTargetFailures() throws {
        let event = try XCTUnwrap(TestEvents.createKeyEvent(type: .keyDown, keyCode: 49))
        let deniedForwarder = PresentationKeyForwarder(
            targetProvider: {
                PresentationKeyForwarder.Target(
                    processIdentifier: 7,
                    applicationName: "Denied Presentation"
                )
            },
            accessChecker: { false },
            accessRequester: { false },
            eventPoster: { _, _, _ in XCTFail("Denied forwarder must not post events") }
        )
        deniedForwarder.beginSession()
        XCTAssertEqual(
            deniedForwarder.forwardKeyDown(event, isEnabled: true, isTextEditing: false),
            .permissionRequired
        )

        let missingTargetForwarder = PresentationKeyForwarder(
            targetProvider: { nil },
            accessChecker: { true },
            accessRequester: { true },
            eventPoster: { _, _, _ in XCTFail("Missing target must not post events") }
        )
        missingTargetForwarder.beginSession()
        XCTAssertEqual(
            missingTargetForwarder.forwardKeyDown(
                event,
                isEnabled: true,
                isTextEditing: false
            ),
            .targetUnavailable
        )
    }

    func testDeniedPresentationPermissionOpensAccessibilitySettings() {
        var didOpenSettings = false
        let deniedForwarder = PresentationKeyForwarder(
            targetProvider: { nil },
            accessChecker: { false },
            accessRequester: { false },
            eventPoster: { _, _, _ in }
        )
        let deniedDelegate = AppDelegate(
            userDefaults: testDefaults,
            presentationKeyForwarder: deniedForwarder,
            presentationPermissionSettingsOpener: {
                didOpenSettings = true
                return true
            }
        )

        XCTAssertFalse(deniedDelegate.requestPresentationNavigationAccess())
        XCTAssertTrue(didOpenSettings)
        XCTAssertTrue(
            testDefaults.bool(forKey: UserDefaults.presentationPostEventAccessRequestedKey)
        )
    }

    func testGrantedPresentationPermissionDoesNotOpenAccessibilitySettings() {
        var didOpenSettings = false
        let grantedForwarder = PresentationKeyForwarder(
            targetProvider: { nil },
            accessChecker: { true },
            accessRequester: { XCTFail("Already granted access must not request again"); return false },
            eventPoster: { _, _, _ in }
        )
        let grantedDelegate = AppDelegate(
            userDefaults: testDefaults,
            presentationKeyForwarder: grantedForwarder,
            presentationPermissionSettingsOpener: {
                didOpenSettings = true
                return true
            }
        )

        XCTAssertTrue(grantedDelegate.requestPresentationNavigationAccess())
        XCTAssertFalse(didOpenSettings)
    }

    func testOverlayWindows() {
        // Test initial setup
        XCTAssertFalse(appDelegate.overlayWindows.isEmpty)

        // Test screen handling
        appDelegate.screenParametersChanged()
        XCTAssertEqual(appDelegate.overlayWindows.count, NSScreen.screens.count)
    }

    func testToolSwitching() {
        appDelegate.enablePenMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .pen)
        }

        appDelegate.enableArrowMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .arrow)
        }
        
        appDelegate.enableLineMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .line)
        }
        
        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(
                currentToolItem.title,
                L10n.format("Current Tool: %@", ToolType.line.displayName)
            )
        }
    }

    func testCounterToolSwitching() {
        appDelegate.enableCounterMode(NSMenuItem())
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .counter)
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(
                currentToolItem.title,
                L10n.format("Current Tool: %@", ToolType.counter.displayName)
            )
        }
    }

    func testColorPicker() throws {
        appDelegate.showColorPicker(nil)
        let popover = try XCTUnwrap(appDelegate.colorPopover)
        XCTAssertNotNil(popover.contentViewController)
        XCTAssertEqual(popover.behavior, .transient)

        // Popover presentation is asynchronous relative to show(relativeTo:)
        // on macOS 26; spin the runloop briefly before checking.
        let deadline = Date(timeIntervalSinceNow: 2)
        while !popover.isShown && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        // Presentation additionally requires an on-screen status item, which
        // headless runners cannot provide; the popover wiring above is still
        // verified there.
        try XCTSkipUnless(
            popover.isShown,
            "Popover did not present; environment has no on-screen status item")
        XCTAssertTrue(popover.isShown)
    }

    // MARK: - Clear Drawings Tests

    func testToggleOverlayClearsDrawingsWhenEnabled() {
        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        appDelegate.alwaysOnMode = false

        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red, lineWidth: 3.0)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue, lineWidth: 3.0)
        overlayWindow.overlayView.arrows.append(testArrow)

        let testLine = Line(startPoint: .zero, endPoint: NSPoint(x: 20, y: 20), color: .green, lineWidth: 3.0)
        overlayWindow.overlayView.lines.append(testLine)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1)

        // Simulate the show behavior from toggleOverlay - clear if setting is enabled
        if testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 0, "Paths should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 0, "Arrows should be cleared when clearDrawingsOnStartKey is true")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 0, "Lines should be cleared when clearDrawingsOnStartKey is true")
    }

    func testToggleOverlayPreservesDrawingsWhenDisabled() {
        testDefaults.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        appDelegate.alwaysOnMode = false

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
        }

        let testPath = DrawingPath(
            points: [
                TimedPoint(point: NSPoint(x: 0, y: 0), timestamp: 0)
            ], color: .red, lineWidth: 3.0)
        overlayWindow.overlayView.paths.append(testPath)

        let testArrow = Arrow(startPoint: .zero, endPoint: NSPoint(x: 10, y: 10), color: .blue, lineWidth: 3.0)
        overlayWindow.overlayView.arrows.append(testArrow)

        let testLine = Line(startPoint: .zero, endPoint: NSPoint(x: 20, y: 20), color: .green, lineWidth: 3.0)
        overlayWindow.overlayView.lines.append(testLine)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1)
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1)

        // Simulate the show behavior from toggleOverlay - clear if setting is enabled
        if testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey) {
            overlayWindow.overlayView.clearAll()
        }
        overlayWindow.makeKeyAndOrderFront(nil)

        XCTAssertEqual(overlayWindow.overlayView.paths.count, 1, "Paths should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.arrows.count, 1, "Arrows should be preserved when clearDrawingsOnStartKey is false")
        XCTAssertEqual(overlayWindow.overlayView.lines.count, 1, "Lines should be preserved when clearDrawingsOnStartKey is false")
    }

    func testClearDrawingsSettingPersistence() {
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        testDefaults.set(true, forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))

        testDefaults.set(false, forKey: UserDefaults.clearDrawingsOnStartKey)
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.clearDrawingsOnStartKey))
    }

    // MARK: - Dock Icon Tests

    func testHideDockIconDefaultValue() {
        testDefaults.removeObject(forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))
    }

    func testDockIconVisibilityPersistence() {
        testDefaults.set(true, forKey: UserDefaults.hideDockIconKey)
        XCTAssertTrue(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))

        testDefaults.set(false, forKey: UserDefaults.hideDockIconKey)
        XCTAssertFalse(testDefaults.bool(forKey: UserDefaults.hideDockIconKey))
    }

    // MARK: - Persist Fade Mode Tests

    func testDefaultFadeModePersistence() {
        testDefaults.removeObject(forKey: UserDefaults.fadeModeKey)
        let persistedFadeMode =
            testDefaults.object(forKey: UserDefaults.fadeModeKey) as? Bool ?? true
        XCTAssertTrue(persistedFadeMode, "Default fade mode should be true (fade mode active).")
    }

    func testToggleFadeModeUpdatesPersistence() {
        let appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))

        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window found")
            return
        }
        XCTAssertTrue(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be true by default.")

        // Toggle fade mode.
        appDelegate.toggleFadeMode(NSMenuItem())

        XCTAssertFalse(
            overlayWindow.overlayView.fadeMode, "Expected fade mode to be false after toggle.")

        // UserDefaults should reflect this change.
        let persistedFadeMode = testDefaults.bool(forKey: UserDefaults.fadeModeKey)
        XCTAssertFalse(persistedFadeMode, "UserDefaults should now store false for fade mode.")
    }

    func testFadeDurationUpdatesAllWindowsAndPersists() {
        appDelegate.updateFadeDuration(4.5)

        XCTAssertEqual(testDefaults.annotationFadeDuration, 4.5, accuracy: 0.001)
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.fadeDuration, 4.5, accuracy: 0.001)
        }
    }

    func testFadeDurationIsClampedToSupportedRange() {
        appDelegate.updateFadeDuration(30)

        XCTAssertEqual(
            testDefaults.annotationFadeDuration,
            annotationFadeDurationRange.upperBound,
            accuracy: 0.001
        )
    }

    func testStatusMenuTrackingPausesCursorWork() {
        guard let menu = appDelegate.statusItem.menu else {
            XCTFail("Status menu not initialized")
            return
        }

        appDelegate.menuWillOpen(menu)
        XCTAssertTrue(appDelegate.isStatusMenuTracking)

        appDelegate.menuDidClose(menu)
        XCTAssertFalse(appDelegate.isStatusMenuTracking)
    }

    func testOverlayWindowsRestorePersistedFadeMode() {
        testDefaults.set(false, forKey: UserDefaults.fadeModeKey)

        let appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))

        // All overlay windows should be initialized with fade mode set to false.
        for window in appDelegate.overlayWindows.values {
            XCTAssertFalse(
                window.overlayView.fadeMode,
                "Overlay window should restore persisted fade mode as false.")
        }
    }

    func testToggleBoardVisibility() {
        let initialState = testDefaults.bool(forKey: UserDefaults.enableBoardKey)

        appDelegate.toggleBoardVisibility(nil)

        let newState = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertNotEqual(initialState, newState, "Board visibility should be toggled")

        appDelegate.toggleBoardVisibility(nil)
        let finalState = testDefaults.bool(forKey: UserDefaults.enableBoardKey)
        XCTAssertEqual(
            initialState, finalState, "Board visibility should be toggled back to original state")
    }

    func testUpdateBoardMenuItems() {
        guard let menu = appDelegate.statusItem.menu else {
            XCTFail("Status bar menu not initialized")
            return
        }

        let toggleBoardItem = menu.items.first {
            $0.action == #selector(AppDelegate.toggleBoardVisibility(_:))
        }
        XCTAssertNotNil(toggleBoardItem, "Board toggle menu item should exist")

        let initialTitle = toggleBoardItem?.title

        let initialState = BoardManager.shared.isEnabled
        BoardManager.shared.isEnabled = !initialState

        appDelegate.updateBoardMenuItems()

        let newTitle = toggleBoardItem?.title
        XCTAssertNotEqual(
            initialTitle, newTitle, "Menu item title should change when board visibility changes")

        BoardManager.shared.isEnabled = initialState
    }

    // MARK: - Toggle Click Effects Tests

    func testPointerEffectsPauseDuringDrawingAndResumeAfterward() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager
        defer { CursorHighlightManager.shared = CursorHighlightManager() }

        cursorManager.clickEffectsEnabled = true
        cursorManager.cursorHighlightEnabled = true

        appDelegate.toggleOverlay()

        XCTAssertTrue(cursorManager.presentationEffectsSuppressed)
        XCTAssertFalse(cursorManager.isActive)
        XCTAssertFalse(cursorManager.shouldShowCursorHighlight)
        XCTAssertTrue(cursorManager.clickEffectsEnabled)
        XCTAssertTrue(cursorManager.cursorHighlightEnabled)

        appDelegate.toggleOverlay()

        XCTAssertFalse(cursorManager.presentationEffectsSuppressed)
        XCTAssertTrue(cursorManager.isActive)
        XCTAssertTrue(cursorManager.shouldShowCursorHighlight)
        XCTAssertTrue(cursorManager.clickEffectsEnabled)
        XCTAssertTrue(cursorManager.cursorHighlightEnabled)
    }

    func testAlwaysOnOverlayDoesNotSuppressPointerEffects() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager
        defer { CursorHighlightManager.shared = CursorHighlightManager() }

        cursorManager.clickEffectsEnabled = true
        cursorManager.cursorHighlightEnabled = true

        appDelegate.toggleAlwaysOnMode()

        XCTAssertFalse(cursorManager.presentationEffectsSuppressed)
        XCTAssertTrue(cursorManager.isActive)
        XCTAssertTrue(cursorManager.shouldShowCursorHighlight)

        appDelegate.toggleAlwaysOnMode()
    }

    func testToggleClickEffectsTogglesBothSettings() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager

        // Start with both disabled
        cursorManager.clickEffectsEnabled = false
        cursorManager.cursorHighlightEnabled = false

        XCTAssertFalse(cursorManager.clickEffectsEnabled)
        XCTAssertFalse(cursorManager.cursorHighlightEnabled)

        // Toggle on - should enable both
        appDelegate.toggleClickEffects(nil)

        XCTAssertTrue(
            CursorHighlightManager.shared.clickEffectsEnabled,
            "clickEffectsEnabled should be true after toggle")
        XCTAssertTrue(
            CursorHighlightManager.shared.cursorHighlightEnabled,
            "cursorHighlightEnabled should be true after toggle")

        // Toggle off - should disable both
        appDelegate.toggleClickEffects(nil)

        XCTAssertFalse(
            CursorHighlightManager.shared.clickEffectsEnabled,
            "clickEffectsEnabled should be false after second toggle")
        XCTAssertFalse(
            CursorHighlightManager.shared.cursorHighlightEnabled,
            "cursorHighlightEnabled should be false after second toggle")

        CursorHighlightManager.shared = CursorHighlightManager()
    }

    func testToggleClickEffectsPostsNotification() {
        let cursorManager = CursorHighlightManager(userDefaults: testDefaults)
        CursorHighlightManager.shared = cursorManager

        cursorManager.clickEffectsEnabled = false
        cursorManager.cursorHighlightEnabled = false

        let expectation = expectation(forNotification: .cursorHighlightStateChanged, object: nil)
        expectation.expectedFulfillmentCount = 2  // One for each property set

        appDelegate.toggleClickEffects(nil)

        wait(for: [expectation], timeout: 1.0)

        CursorHighlightManager.shared = CursorHighlightManager()
    }

    // MARK: - Previous Tool Tracking Tests

    func testSwitchToolSavesPreviousToolForTextMode() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableArrowMode(NSMenuItem())
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.enableTextMode(NSMenuItem())

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .text)
        XCTAssertEqual(overlayWindow.overlayView.previousTool, .arrow, "previousTool should be .arrow after switching from arrow to text")
    }

    func testSwitchToolDoesNotSavePreviousToolForOtherModes() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        overlayWindow.overlayView.previousTool = .pen
        appDelegate.enableArrowMode(NSMenuItem())

        let previousToolBefore = overlayWindow.overlayView.previousTool
        appDelegate.enableLineMode(NSMenuItem())

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .line)
        XCTAssertEqual(overlayWindow.overlayView.previousTool, previousToolBefore, "previousTool should remain unchanged when not switching to text mode")
    }

    // MARK: - Default Tool Tests

    func testSwitchToolPersistsLastUsedTool() {
        appDelegate.enableRectangleMode(NSMenuItem())
        XCTAssertEqual(testDefaults.lastUsedTool, .rectangle, "Explicitly switching tools should persist the choice as last used")

        appDelegate.enableHighlighterMode(NSMenuItem())
        XCTAssertEqual(testDefaults.lastUsedTool, .highlighter)
    }

    func testApplyConfiguredDefaultToolAppliesSpecificTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        testDefaults.defaultToolOption = .tool(.rectangle)
        appDelegate.enableArrowMode(NSMenuItem())  // start on a different tool than the configured default
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .rectangle, "Activation should reset the tool to the configured default")
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(
                currentToolItem.title,
                L10n.format("Current Tool: %@", ToolType.rectangle.displayName)
            )
        }
    }

    func testApplyConfiguredDefaultToolSkipsWhenToolAlreadyActive() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableRectangleMode(NSMenuItem())
        testDefaults.defaultToolOption = .tool(.rectangle)
        testDefaults.lastUsedTool = .highlighter

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.lastUsedTool, .highlighter,
            "Applying a default tool that is already active should be a no-op (no switchTool, no tool feedback)")
    }

    func testApplyConfiguredDefaultToolDoesNotOverwriteLastUsedTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        appDelegate.enableHighlighterMode(NSMenuItem())
        testDefaults.defaultToolOption = .tool(.rectangle)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .rectangle)
        XCTAssertEqual(
            testDefaults.lastUsedTool, .highlighter,
            "Applying the configured default is not an explicit selection and must not overwrite the persisted last-used tool")
    }

    func testApplyConfiguredDefaultToolDoesNothingForLastUsed() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        XCTAssertEqual(testDefaults.defaultToolOption, .lastUsed, "Default should be Last Used until the setting is touched")

        appDelegate.enableArrowMode(NSMenuItem())
        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow)

        appDelegate.applyConfiguredDefaultTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .arrow, "Last Used should preserve whatever tool was already active")
    }

    func testLaunchRestoresPersistedLastUsedTool() {
        testDefaults.lastUsedTool = .highlighter

        let appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))

        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .highlighter, "Overlay windows should restore the persisted last-used tool on launch")
        }

        if let menu = appDelegate.statusItem.menu,
            let currentToolItem = menu.item(at: 3)  // Index 3 is "Current Tool" menu item
        {
            XCTAssertEqual(
                currentToolItem.title,
                L10n.format("Current Tool: %@", ToolType.highlighter.displayName),
                "Menu should reflect the restored tool, not the hardcoded default"
            )
        }
    }

    func testLaunchDefaultsToPenWhenNoLastUsedToolSaved() {
        // testDefaults is a fresh suite with no LastUsedTool key set (see setUp).
        for window in appDelegate.overlayWindows.values {
            XCTAssertEqual(window.overlayView.currentTool, .pen, "Should fall back to .pen when no last-used tool was saved")
        }
    }

    func testInternalToolRestoreDoesNotOverwriteLastUsedTool() {
        guard let overlayWindow = appDelegate.overlayWindows.values.first else {
            XCTFail("No overlay window available")
            return
        }

        // restorePreviousTool reads persistTextMode from UserDefaults.standard, so pin it
        // to false for this test and restore whatever was there afterwards.
        let savedPersistTextMode = UserDefaults.standard.object(forKey: UserDefaults.persistTextModeKey)
        UserDefaults.standard.set(false, forKey: UserDefaults.persistTextModeKey)
        defer {
            if let saved = savedPersistTextMode {
                UserDefaults.standard.set(saved, forKey: UserDefaults.persistTextModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaults.persistTextModeKey)
            }
        }

        appDelegate.enablePenMode(NSMenuItem())
        appDelegate.enableTextMode(NSMenuItem())
        XCTAssertEqual(testDefaults.lastUsedTool, .text, "Explicitly switching to text should persist it as last used")
        XCTAssertEqual(overlayWindow.overlayView.previousTool, .pen)

        overlayWindow.overlayView.restorePreviousTool()

        XCTAssertEqual(overlayWindow.overlayView.currentTool, .pen, "Finishing a text annotation should restore the previous tool")
        XCTAssertEqual(testDefaults.lastUsedTool, .text, "Internal tool restores should not overwrite the persisted last-used tool")
    }
}
