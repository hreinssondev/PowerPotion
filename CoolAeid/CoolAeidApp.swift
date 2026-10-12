import AppKit
import Carbon.HIToolbox
import Combine
import Darwin
import SwiftUI

@main
struct CoolAeidApp: App {
    @NSApplicationDelegateAdaptor(CoolAeidAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CoolAeidAppDelegate: NSObject, NSApplicationDelegate {
    private let pipCoordinator: AppCoordinator
    private let dockMoverModel: DockMoverModel
    private let windowBuddyModel: WindowBuddyModel
    private let dockMoverSettingsPresenter: DockMoverSettingsWindowPresenter
    private let windowBuddySettingsPresenter: WindowBuddySettingsWindowPresenter
    private let finderLastWindowHider: FinderLastWindowHider
    private let dockClickAppHider: DockClickAppHider
    private var windowBuddyHotKeyController: WindowBuddyHotKeyController?
    private var windowBuddySettingsShortcutCancellable: AnyCancellable?
    private var windowBuddyShortcutCancellable: AnyCancellable?
    private var windowBuddyPhysicalKeyCancellable: AnyCancellable?
    private var cycleAppWindowsShortcutCancellable: AnyCancellable?
    private var dockClickAppHiderCancellable: AnyCancellable?
    private var statusBarController: CoolAeidStatusBarController?

    override init() {
        Self.exitIfThisIsASecondaryInstance()
        LegacyPreferencesMigrator.migrateIfNeeded()
        pipCoordinator = AppCoordinator()
        dockMoverModel = DockMoverModel()
        windowBuddyModel = WindowBuddyModel()
        dockMoverSettingsPresenter = DockMoverSettingsWindowPresenter()
        windowBuddySettingsPresenter = WindowBuddySettingsWindowPresenter()
        finderLastWindowHider = FinderLastWindowHider()
        dockClickAppHider = DockClickAppHider()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowBuddyModel.applyActivationPolicy()
        dockMoverModel.setSettingsWindowOpener { [weak self] in
            self?.openDockMoverSettings()
        }

        configureWindowBuddyHotKeys()
        finderLastWindowHider.start()
        configureDockClickAppHider()
        windowBuddyModel.start()

        statusBarController = CoolAeidStatusBarController(
            coordinator: pipCoordinator,
            openDockMoverSettings: { [weak self] in
                self?.openDockMoverSettings()
            },
            openWindowBuddySettings: { [weak self] in
                self?.openWindowBuddySettings()
            }
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.showMenu()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        windowBuddyHotKeyController?.start()
        if windowBuddyModel.hidesFrontmostAppOnDockClick {
            // The event tap can only be created once Accessibility is granted.
            dockClickAppHider.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowBuddyHotKeyController?.stop()
        dockClickAppHider.stop()
    }

    private static func exitIfThisIsASecondaryInstance() {
        let ownProcessIdentifier = NSRunningApplication.current.processIdentifier
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let ownBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let ownIsInstalledApp = ownBundlePath == "/Applications/CoolAeid.app"

        let otherInstances = NSWorkspace.shared.runningApplications.filter { application in
            application.processIdentifier != ownProcessIdentifier &&
                application.bundleIdentifier == ownBundleIdentifier
        }

        guard !otherInstances.isEmpty else { return }

        if ownIsInstalledApp {
            for application in otherInstances {
                application.terminate()
            }
        } else {
            Darwin.exit(0)
        }
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    private func configureWindowBuddyHotKeys() {
        let hotKeyController = WindowBuddyHotKeyController { [weak self] action in
            guard let self else {
                return
            }

            switch action {
            case .fillFrontmostWindowAndTemporarilyRemoveFromTiling:
                windowBuddyModel.fillFrontmostWindowAndTemporarilyRemoveFromTiling()
            case .restoreMostRecentlyRemovedWindowToTiling:
                windowBuddyModel.restoreMostRecentlyRemovedWindowToTiling()
            case .moveFocusedTiledWindowLeft:
                windowBuddyModel.moveFrontmostTiledWindow(.left)
            case .moveFocusedTiledWindowRight:
                windowBuddyModel.moveFrontmostTiledWindow(.right)
            case .toggleFocusGroupsForward:
                windowBuddyModel.toggleFocusGroups()
            case .toggleFocusGroupsBackward:
                windowBuddyModel.toggleFocusGroups(reverse: true)
            case .toggleSecondaryFocusGroupsForward:
                windowBuddyModel.toggleFocusGroups(number: 2)
            case .toggleSecondaryFocusGroupsBackward:
                windowBuddyModel.toggleFocusGroups(reverse: true, number: 2)
            case .cycleFrontmostAppWindows:
                windowBuddyModel.cycleFrontmostAppWindows()
            case .openSettings:
                openWindowBuddySettings()
            }
        }
        hotKeyController.settingsShortcut = windowBuddyModel.settingsShortcut
        hotKeyController.cycleAppWindowsShortcut = windowBuddyModel.cycleAppWindowsShortcut
        hotKeyController.focusGroupsForwardShortcut = windowBuddyModel.focusGroupsForwardShortcut
        hotKeyController.focusGroupsBackwardShortcut = windowBuddyModel.focusGroupsBackwardShortcut
        hotKeyController.updateFocusGroupPhysicalKeys(groupOne: windowBuddyModel.focusGroupOnePhysicalKey,
                                                      groupTwo: windowBuddyModel.focusGroupTwoPhysicalKey)
        hotKeyController.start()
        windowBuddySettingsShortcutCancellable = windowBuddyModel.$settingsShortcut
            .dropFirst()
            .sink { [weak hotKeyController] settingsShortcut in
                hotKeyController?.updateSettingsShortcut(settingsShortcut)
            }
        cycleAppWindowsShortcutCancellable = windowBuddyModel.$cycleAppWindowsShortcut
            .dropFirst()
            .sink { [weak hotKeyController] shortcut in
                hotKeyController?.updateCycleAppWindowsShortcut(shortcut)
            }
        windowBuddyShortcutCancellable = Publishers.CombineLatest(
            windowBuddyModel.$focusGroupsForwardShortcut,
            windowBuddyModel.$focusGroupsBackwardShortcut
        )
        .dropFirst()
        .sink { [weak hotKeyController] forwardShortcut, backwardShortcut in
            hotKeyController?.updateFocusGroupShortcuts(forward: forwardShortcut,
                                                        backward: backwardShortcut)
        }
        windowBuddyPhysicalKeyCancellable = Publishers.CombineLatest(
            windowBuddyModel.$focusGroupOnePhysicalKey,
            windowBuddyModel.$focusGroupTwoPhysicalKey
        )
        .dropFirst()
        .sink { [weak hotKeyController] groupOneKey, groupTwoKey in
            hotKeyController?.updateFocusGroupPhysicalKeys(groupOne: groupOneKey,
                                                           groupTwo: groupTwoKey)
        }
        windowBuddyHotKeyController = hotKeyController
    }

    private func configureDockClickAppHider() {
        dockClickAppHiderCancellable = windowBuddyModel.$hidesFrontmostAppOnDockClick
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }

                if isEnabled {
                    dockClickAppHider.start()
                } else {
                    dockClickAppHider.stop()
                }
            }
    }

    private func openDockMoverSettings() {
        dockMoverSettingsPresenter.show(model: dockMoverModel)
    }

    private func openWindowBuddySettings() {
        windowBuddySettingsPresenter.show(model: windowBuddyModel)
    }
}

private enum LegacyPreferencesMigrator {
    private static let migrationMarkerKey = "CoolAeid.legacyPreferencesMigrated.v1"

    private static let anyPIPKeys: Set<String> = [
        "DoubleTapHotkeyInput",
        "DoubleTapKeyInput",
        "DoubleTapShortcutMode",
        "DoubleTapSingleKeyInput",
        "HotkeyInput",
        "HoverSwitchEnabled",
        "PiPWindowFrame",
        "PrimaryDoubleTapKeyInput",
        "PrimaryShortcutMode",
        "PrimarySingleKeyInput"
    ]

    private static let windowBuddyKeys: Set<String> = [
        "activeFocusGroupIdentifier",
        "activeSecondaryFocusGroupIdentifier",
        "autoTileAppBundleIdentifiers",
        "autoTileAppGroups",
        "autoTilingEnabled",
        "existingFirstNewWindowBundleIdentifiers",
        "excludesManuallyMovedWindowsFromAutoTiling",
        "fillsFirstWindowByGroup",
        "focusedAutoTileWindowWidthFraction",
        "focusGroupIdentifiers",
        "focusGroupOnePhysicalKeyCode",
        "focusGroupSwitchDelay",
        "focusGroupTwoPhysicalKeyCode",
        "focusedGroupNumberByGroup",
        "focusTileWiderFixedBundleIdentifiers",
        "ignoredSecondWindowStartModeByGroup",
        "ignoresSecondAppInList",
        "ignoresSecondAppInListByGroup",
        "instantWindowMovement",
        "keepsFullSizeWindowsOutOfAutoTiling",
        "mainAppBundleIdentifiersByGroup",
        "maximumColumnCountByGroup",
        "movesExistingAutoTileAppWindowsToFocusedGroup",
        "revealsActiveAutoTileGroupApps",
        "screenLayoutModeByGroup",
        "showsDockIcon",
        "switchesAwayFromSingleAppFocusGroups",
        "tileDirectionByGroup",
        "widensFocusedAutoTileWindow"
    ]

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationMarkerKey) else {
            return
        }

        migrateDomain("AnyPIP.AnyPIP") { anyPIPKeys.contains($0) }
        migrateDomain("Dockmover.DockMover") { $0.hasPrefix("DockMover.") }
        migrateDomain("com.windowbuddy.WindowBuddy") { windowBuddyKeys.contains($0) }

        defaults.set(true, forKey: migrationMarkerKey)
        defaults.synchronize()
    }

    private static func migrateDomain(
        _ domain: String,
        shouldCopyKey: (String) -> Bool
    ) {
        guard let preferences = UserDefaults.standard.persistentDomain(forName: domain) else {
            return
        }

        let defaults = UserDefaults.standard
        for (key, value) in preferences where shouldCopyKey(key) {
            defaults.set(value, forKey: key)
        }
    }
}

@MainActor
final class MenuBarIconSelection: ObservableObject {
    @Published var iconName: String

    init(iconName: String) {
        self.iconName = iconName
    }

    var image: NSImage {
        let image = MenuBarIconLibrary.image(named: iconName, accessibilityDescription: "Menu bar icon")
            ?? MenuBarIconLibrary.image(
                named: MenuBarIconLibrary.customFlaskOpenName,
                accessibilityDescription: "Menu bar icon"
            )
            ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

@MainActor
final class CoolAeidStatusBarController: NSObject, NSPopoverDelegate {
    private static let defaultMenuBarIconName = MenuBarIconLibrary.customFlaskOpenName
    private static let menuBarIconNameKey = "CoolAeid.MenuBarIconName"

    private let coordinator: AppCoordinator
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let iconPickerPresenter = MenuBarIconPickerWindowPresenter()
    private let menuBarIconSelection: MenuBarIconSelection
    private var pendingDeactivateWorkItem: DispatchWorkItem?

    init(
        coordinator: AppCoordinator,
        openDockMoverSettings: @escaping () -> Void,
        openWindowBuddySettings: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menuBarIconSelection = MenuBarIconSelection(
            iconName: UserDefaults.standard.string(forKey: Self.menuBarIconNameKey) ?? Self.defaultMenuBarIconName
        )
        super.init()

        // Allow ⌘-dragging the item out of the menu bar, with or without a
        // Dock icon. Every launch brings it back, overriding the visibility
        // AppKit autosaved on removal, and reopening the app (Finder,
        // Spotlight, Dock) restores it via showMenu().
        statusItem.autosaveName = "CoolAeid.StatusItem"
        statusItem.behavior = .removalAllowed
        statusItem.isVisible = true

        if let button = statusItem.button {
            applyMenuBarIcon()
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        popover.animates = false
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: AnyPIPMenuView(
                menuBarIconSelection: menuBarIconSelection,
                closeMenuBarExtra: { [weak self] in
                    self?.closePopover()
                },
                openDockMoverSettings: openDockMoverSettings,
                openWindowBuddySettings: openWindowBuddySettings,
                openMenuBarIconPicker: { [weak self] in
                    self?.showIconPicker()
                }
            )
            .environmentObject(coordinator)
        )
    }

    func showMenu() {
        guard statusItem.isVisible else {
            statusItem.isVisible = true
            // Let the menu bar lay out the restored button before anchoring the popover.
            DispatchQueue.main.async { [weak self] in
                self?.showMenu()
            }
            return
        }

        guard let button = statusItem.button else {
            return
        }

        showPopover(relativeTo: button)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: sender)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        pendingDeactivateWorkItem?.cancel()
        pendingDeactivateWorkItem = nil
        coordinator.refreshPermissions()
        button.highlight(true)
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePopover() {
        popover.close()
        statusItem.button?.highlight(false)
        pendingDeactivateWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            NSApp.deactivate()
        }
        pendingDeactivateWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    private func showIconPicker() {
        pendingDeactivateWorkItem?.cancel()
        pendingDeactivateWorkItem = nil
        popover.close()
        statusItem.button?.highlight(false)
        iconPickerPresenter.show(selectedIconName: menuBarIconSelection.iconName) { [weak self] iconName in
            self?.setMenuBarIcon(iconName)
        }
    }

    private func setMenuBarIcon(_ iconName: String) {
        let trimmedIconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.menuBarImage(named: trimmedIconName) != nil else {
            NSSound.beep()
            return
        }

        menuBarIconSelection.iconName = trimmedIconName
        UserDefaults.standard.set(trimmedIconName, forKey: Self.menuBarIconNameKey)
        applyMenuBarIcon()
    }

    private func applyMenuBarIcon() {
        guard let button = statusItem.button else {
            return
        }

        if let image = Self.menuBarImage(named: menuBarIconSelection.iconName) {
            button.image = image
        } else {
            menuBarIconSelection.iconName = Self.defaultMenuBarIconName
            UserDefaults.standard.set(Self.defaultMenuBarIconName, forKey: Self.menuBarIconNameKey)
            applyMenuBarIcon()
        }
    }

    private static func menuBarImage(named iconName: String) -> NSImage? {
        guard let image = MenuBarIconLibrary.image(named: iconName, accessibilityDescription: "CoolAeid") else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

@MainActor
private final class DockMoverSettingsWindowPresenter {
    private var windowController: NSWindowController?

    func show(model: DockMoverModel) {
        let controller = windowController ?? makeWindowController(model: model)
        windowController = controller

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.window?.orderFrontRegardless()
    }

    private func makeWindowController(model: DockMoverModel) -> NSWindowController {
        let rootView = DockMoverSettingsView(model: model)
            .frame(
                minWidth: 720,
                idealWidth: 900,
                maxWidth: .infinity
            )
            .background(SettingsWindowProbe { window in
                model.configureSettingsWindow(window)
            })

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "DockMover"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.setContentSize(NSSize(width: 900, height: 240))
        window.minSize = NSSize(width: 720, height: 140)
        window.center()
        model.configureSettingsWindow(window)

        return NSWindowController(window: window)
    }
}

@MainActor
private final class WindowBuddySettingsWindowPresenter {
    private var windowController: NSWindowController?

    func show(model: WindowBuddyModel) {
        let controller = windowController ?? makeWindowController(model: model)
        windowController = controller

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.window?.orderFrontRegardless()
    }

    private func makeWindowController(model: WindowBuddyModel) -> NSWindowController {
        let hostingController = NSHostingController(rootView: WindowBuddySettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WindowBuddy Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.setContentSize(NSSize(width: 920, height: 680))
        window.minSize = NSSize(width: 860, height: 620)
        window.center()

        return NSWindowController(window: window)
    }
}

private struct SettingsWindowProbe: NSViewRepresentable {
    let onWindowChange: (NSWindow) -> Void

    func makeNSView(context: Context) -> SettingsWindowProbeView {
        let view = SettingsWindowProbeView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ view: SettingsWindowProbeView, context: Context) {
        view.onWindowChange = onWindowChange
        if let window = view.window {
            onWindowChange(window)
        }
    }
}

private final class SettingsWindowProbeView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window {
            onWindowChange?(window)
        }
    }
}

enum WindowBuddyHotKeyAction {
    case fillFrontmostWindowAndTemporarilyRemoveFromTiling
    case restoreMostRecentlyRemovedWindowToTiling
    case moveFocusedTiledWindowLeft
    case moveFocusedTiledWindowRight
    case toggleFocusGroupsForward
    case toggleFocusGroupsBackward
    case toggleSecondaryFocusGroupsForward
    case toggleSecondaryFocusGroupsBackward
    case cycleFrontmostAppWindows
    case openSettings
}

private final class WindowBuddyHotKeyController {
    fileprivate static let signature: OSType = 0x57424459
    fileprivate typealias Handler = @MainActor (WindowBuddyHotKeyAction) -> Void
    private static let registrationRetryDelays: [TimeInterval] = [0.1, 0.25, 0.5, 1, 2, 4]

    private enum Identifier: UInt32, CaseIterable {
        case fillFrontmostWindowAndTemporarilyRemoveFromTiling = 1
        case restoreMostRecentlyRemovedWindowToTiling = 2
        case moveFocusedTiledWindowLeft = 3
        case moveFocusedTiledWindowRight = 4
        case toggleFocusGroupsForward = 6
        case toggleFocusGroupsBackward = 7
        case toggleSecondaryFocusGroupsForward = 9
        case toggleSecondaryFocusGroupsBackward = 10
        case physicalFocusGroupsForward = 11
        case physicalFocusGroupsBackward = 12
        case physicalSecondaryFocusGroupsForward = 13
        case physicalSecondaryFocusGroupsBackward = 14
        case cycleFrontmostAppWindows = 15
        case openSettings = 8

        var action: WindowBuddyHotKeyAction {
            switch self {
            case .fillFrontmostWindowAndTemporarilyRemoveFromTiling:
                .fillFrontmostWindowAndTemporarilyRemoveFromTiling
            case .restoreMostRecentlyRemovedWindowToTiling:
                .restoreMostRecentlyRemovedWindowToTiling
            case .moveFocusedTiledWindowLeft:
                .moveFocusedTiledWindowLeft
            case .moveFocusedTiledWindowRight:
                .moveFocusedTiledWindowRight
            case .toggleFocusGroupsForward, .physicalFocusGroupsForward:
                .toggleFocusGroupsForward
            case .toggleFocusGroupsBackward, .physicalFocusGroupsBackward:
                .toggleFocusGroupsBackward
            case .toggleSecondaryFocusGroupsForward, .physicalSecondaryFocusGroupsForward:
                .toggleSecondaryFocusGroupsForward
            case .toggleSecondaryFocusGroupsBackward, .physicalSecondaryFocusGroupsBackward:
                .toggleSecondaryFocusGroupsBackward
            case .cycleFrontmostAppWindows:
                .cycleFrontmostAppWindows
            case .openSettings:
                .openSettings
            }
        }
    }

    private let handler: Handler
    private let focusGroupPhysicalKeyController: FocusGroupPhysicalKeyController
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [Identifier: EventHotKeyRef] = [:]
    private var registrationRetryTimer: Timer?
    private var registrationRetryIndex = 0
    private var focusGroupOnePhysicalKey: FocusGroupPhysicalKey = .groupOneDefault
    private var focusGroupTwoPhysicalKey: FocusGroupPhysicalKey = .groupTwoDefault
    var settingsShortcut: DockMoverShortcut = .windowBuddySettingsDefault
    var cycleAppWindowsShortcut: DockMoverShortcut = .cycleAppWindowsDefault
    var focusGroupsForwardShortcut: DockMoverShortcut = .focusGroupsForwardDefault
    var focusGroupsBackwardShortcut: DockMoverShortcut = .focusGroupsBackwardDefault

    init(handler: @escaping Handler) {
        self.handler = handler
        focusGroupPhysicalKeyController = FocusGroupPhysicalKeyController { command in
            let action: WindowBuddyHotKeyAction
            switch (command.groupNumber, command.reverse) {
            case (1, false):
                action = .toggleFocusGroupsForward
            case (1, true):
                action = .toggleFocusGroupsBackward
            case (2, false):
                action = .toggleSecondaryFocusGroupsForward
            case (2, true):
                action = .toggleSecondaryFocusGroupsBackward
            default:
                return
            }

            handler(action)
        }
    }

    deinit {
        stop()
    }

    func start() {
        if eventHandler != nil {
            restartRegistrationReconciliation()
            focusGroupPhysicalKeyController.start()
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let eventHandlerStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                     windowBuddyHotKeyCallback,
                                                     1,
                                                     &eventType,
                                                     userData,
                                                     &eventHandler)
        guard eventHandlerStatus == noErr, eventHandler != nil else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            focusGroupPhysicalKeyController.updateCarbonHandledCommands([])
            focusGroupPhysicalKeyController.start()
            return
        }

        restartRegistrationReconciliation()
        focusGroupPhysicalKeyController.start()
    }

    func stop() {
        cancelRegistrationRetries(resetIndex: true)
        focusGroupPhysicalKeyController.updateCarbonHandledCommands([])
        focusGroupPhysicalKeyController.stop()

        for hotKey in hotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys = [:]

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleHotKey(identifier: UInt32) {
        guard let identifier = Identifier(rawValue: identifier) else {
            return
        }

        handler(identifier.action)
    }

    func updateSettingsShortcut(_ shortcut: DockMoverShortcut) {
        settingsShortcut = shortcut

        guard eventHandler != nil else {
            return
        }

        unregisterHotKey(identifier: .openSettings)
        restartRegistrationReconciliation()
    }

    func updateCycleAppWindowsShortcut(_ shortcut: DockMoverShortcut) {
        cycleAppWindowsShortcut = shortcut

        guard eventHandler != nil else {
            return
        }

        unregisterHotKey(identifier: .cycleFrontmostAppWindows)
        restartRegistrationReconciliation()
    }

    func updateFocusGroupShortcuts(forward: DockMoverShortcut,
                                   backward: DockMoverShortcut) {
        focusGroupsForwardShortcut = forward
        focusGroupsBackwardShortcut = backward

        guard eventHandler != nil else {
            return
        }

        unregisterHotKey(identifier: .toggleFocusGroupsForward)
        unregisterHotKey(identifier: .toggleFocusGroupsBackward)
        restartRegistrationReconciliation()
    }

    func updateFocusGroupPhysicalKeys(groupOne: FocusGroupPhysicalKey,
                                      groupTwo: FocusGroupPhysicalKey) {
        focusGroupOnePhysicalKey = groupOne
        focusGroupTwoPhysicalKey = groupTwo
        focusGroupPhysicalKeyController.updateBindings(groupOneKey: groupOne,
                                                       groupTwoKey: groupTwo)

        guard eventHandler != nil else {
            return
        }

        unregisterPhysicalFocusGroupHotKeys()
        restartRegistrationReconciliation()
    }

    private func restartRegistrationReconciliation() {
        cancelRegistrationRetries(resetIndex: true)
        reconcileHotKeyRegistrations()
    }

    private func reconcileHotKeyRegistrations() {
        guard eventHandler != nil else {
            return
        }

        registerHotKeyIfNeeded(keyCode: UInt32(kVK_UpArrow),
                               modifiers: UInt32(optionKey),
                               identifier: .fillFrontmostWindowAndTemporarilyRemoveFromTiling)
        registerHotKeyIfNeeded(keyCode: UInt32(kVK_DownArrow),
                               modifiers: UInt32(optionKey),
                               identifier: .restoreMostRecentlyRemovedWindowToTiling)
        registerHotKeyIfNeeded(keyCode: UInt32(kVK_LeftArrow),
                               modifiers: UInt32(controlKey | optionKey),
                               identifier: .moveFocusedTiledWindowLeft)
        registerHotKeyIfNeeded(keyCode: UInt32(kVK_RightArrow),
                               modifiers: UInt32(controlKey | optionKey),
                               identifier: .moveFocusedTiledWindowRight)
        registerHotKeyIfNeeded(focusGroupsForwardShortcut,
                               identifier: .toggleFocusGroupsForward)
        registerHotKeyIfNeeded(focusGroupsBackwardShortcut,
                               identifier: .toggleFocusGroupsBackward)
        registerHotKeyIfNeeded(.secondaryFocusGroupsForwardDefault,
                               identifier: .toggleSecondaryFocusGroupsForward)
        registerHotKeyIfNeeded(.secondaryFocusGroupsBackwardDefault,
                               identifier: .toggleSecondaryFocusGroupsBackward)
        registerHotKeyIfNeeded(cycleAppWindowsShortcut,
                               identifier: .cycleFrontmostAppWindows)
        registerHotKeyIfNeeded(settingsShortcut,
                               identifier: .openSettings)
        registerPhysicalFocusGroupHotKeys()

        if Identifier.allCases.allSatisfy({ hotKeys[$0] != nil }) {
            cancelRegistrationRetries(resetIndex: true)
        } else {
            scheduleRegistrationRetryIfNeeded()
        }
    }

    private func scheduleRegistrationRetryIfNeeded() {
        guard registrationRetryTimer == nil,
              registrationRetryIndex < Self.registrationRetryDelays.count,
              eventHandler != nil else {
            return
        }

        let delay = Self.registrationRetryDelays[registrationRetryIndex]
        registrationRetryIndex += 1
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }

            self.registrationRetryTimer = nil
            self.reconcileHotKeyRegistrations()
        }
        RunLoop.main.add(timer, forMode: .common)
        registrationRetryTimer = timer
    }

    private func cancelRegistrationRetries(resetIndex: Bool) {
        registrationRetryTimer?.invalidate()
        registrationRetryTimer = nil
        if resetIndex {
            registrationRetryIndex = 0
        }
    }

    @discardableResult
    private func registerHotKey(_ shortcut: DockMoverShortcut,
                                identifier: Identifier) -> Bool {
        registerHotKey(keyCode: UInt32(shortcut.keyCode),
                       modifiers: shortcut.carbonModifiers,
                       identifier: identifier)
    }

    @discardableResult
    private func registerHotKeyIfNeeded(_ shortcut: DockMoverShortcut,
                                        identifier: Identifier) -> Bool {
        if hotKeys[identifier] != nil {
            return true
        }

        return registerHotKey(shortcut, identifier: identifier)
    }

    @discardableResult
    private func registerHotKeyIfNeeded(keyCode: UInt32,
                                        modifiers: UInt32,
                                        identifier: Identifier) -> Bool {
        if hotKeys[identifier] != nil {
            return true
        }

        return registerHotKey(keyCode: keyCode,
                              modifiers: modifiers,
                              identifier: identifier)
    }

    @discardableResult
    private func registerHotKey(keyCode: UInt32,
                                modifiers: UInt32,
                                identifier: Identifier) -> Bool {
        unregisterHotKey(identifier: identifier)
        let hotKeyID = EventHotKeyID(signature: Self.signature,
                                     id: identifier.rawValue)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode,
                                          modifiers,
                                          hotKeyID,
                                          GetApplicationEventTarget(),
                                          0,
                                          &hotKey)

        guard status == noErr,
              let hotKey else {
            return false
        }

        hotKeys[identifier] = hotKey
        return true
    }

    private func unregisterHotKey(identifier: Identifier) {
        guard let hotKey = hotKeys.removeValue(forKey: identifier) else {
            return
        }

        UnregisterEventHotKey(hotKey)
    }

    private func registerPhysicalFocusGroupHotKeys() {
        let registrations: [(Identifier, FocusGroupPhysicalKey, FocusGroupCycleCommand)] = [
            (.physicalFocusGroupsForward,
             focusGroupOnePhysicalKey,
             FocusGroupCycleCommand(groupNumber: 1, reverse: false)),
            (.physicalFocusGroupsBackward,
             focusGroupOnePhysicalKey,
             FocusGroupCycleCommand(groupNumber: 1, reverse: true)),
            (.physicalSecondaryFocusGroupsForward,
             focusGroupTwoPhysicalKey,
             FocusGroupCycleCommand(groupNumber: 2, reverse: false)),
            (.physicalSecondaryFocusGroupsBackward,
             focusGroupTwoPhysicalKey,
             FocusGroupCycleCommand(groupNumber: 2, reverse: true))
        ]
        var carbonHandledCommands: Set<FocusGroupCycleCommand> = []

        for (identifier, physicalKey, command) in registrations {
            let modifiers = command.reverse ? UInt32(cmdKey) : 0
            if registerHotKeyIfNeeded(keyCode: Self.carbonKeyCode(for: physicalKey),
                                      modifiers: modifiers,
                                      identifier: identifier) {
                carbonHandledCommands.insert(command)
            }
        }

        focusGroupPhysicalKeyController.updateCarbonHandledCommands(carbonHandledCommands)
    }

    private func unregisterPhysicalFocusGroupHotKeys() {
        unregisterHotKey(identifier: .physicalFocusGroupsForward)
        unregisterHotKey(identifier: .physicalFocusGroupsBackward)
        unregisterHotKey(identifier: .physicalSecondaryFocusGroupsForward)
        unregisterHotKey(identifier: .physicalSecondaryFocusGroupsBackward)
        focusGroupPhysicalKeyController.updateCarbonHandledCommands([])
    }

    private static func carbonKeyCode(for physicalKey: FocusGroupPhysicalKey) -> UInt32 {
        if physicalKey.keyCode == UInt16(kVK_CapsLock) {
            return UInt32(kVK_F17)
        }

        return UInt32(physicalKey.keyCode)
    }
}

private let windowBuddyHotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event,
          let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr,
          hotKeyID.signature == WindowBuddyHotKeyController.signature else {
        return OSStatus(eventNotHandledErr)
    }

    let controller = Unmanaged<WindowBuddyHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleHotKey(identifier: hotKeyID.id)
    return noErr
}
