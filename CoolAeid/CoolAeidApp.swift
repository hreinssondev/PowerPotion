import AppKit
import Carbon.HIToolbox
import Combine
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
    private var windowBuddyHotKeyController: WindowBuddyHotKeyController?
    private var statusBarController: CoolAeidStatusBarController?

    override init() {
        LegacyPreferencesMigrator.migrateIfNeeded()
        pipCoordinator = AppCoordinator()
        dockMoverModel = DockMoverModel()
        windowBuddyModel = WindowBuddyModel()
        dockMoverSettingsPresenter = DockMoverSettingsWindowPresenter()
        windowBuddySettingsPresenter = WindowBuddySettingsWindowPresenter()
        finderLastWindowHider = FinderLastWindowHider()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowBuddyModel.applyActivationPolicy()
        dockMoverModel.setSettingsWindowOpener { [weak self] in
            self?.openDockMoverSettings()
        }

        configureWindowBuddyHotKeys()
        finderLastWindowHider.start()
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
            case .resizeAutoTiledWindows:
                windowBuddyModel.resizeAutoTiledWindows()
            case .toggleFocusGroups:
                windowBuddyModel.toggleFocusGroups()
            case .openSettings:
                openWindowBuddySettings()
            }
        }
        hotKeyController.start()
        windowBuddyHotKeyController = hotKeyController
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
        "autoTileAppBundleIdentifiers",
        "autoTileAppGroups",
        "autoTilingEnabled",
        "existingFirstNewWindowBundleIdentifiers",
        "fillsFirstWindowByGroup",
        "focusedAutoTileWindowWidthFraction",
        "focusGroupIdentifiers",
        "focusTileWiderFixedBundleIdentifiers",
        "ignoredSecondWindowStartModeByGroup",
        "ignoresSecondAppInList",
        "ignoresSecondAppInListByGroup",
        "instantWindowMovement",
        "mainAppBundleIdentifiersByGroup",
        "maximumColumnCountByGroup",
        "movesExistingAutoTileAppWindowsToFocusedGroup",
        "revealsActiveAutoTileGroupApps",
        "screenLayoutModeByGroup",
        "showsDockIcon",
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
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Menu bar icon")
            ?? NSImage(systemSymbolName: "pip", accessibilityDescription: "Menu bar icon")
            ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

@MainActor
final class CoolAeidStatusBarController: NSObject, NSPopoverDelegate {
    private static let defaultMenuBarIconName = "pip"
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
        guard let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "CoolAeid") else {
            return nil
        }

        image.isTemplate = true
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
                maxWidth: .infinity,
                minHeight: 320,
                idealHeight: 320,
                maxHeight: .infinity
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
        window.setContentSize(NSSize(width: 900, height: 320))
        window.minSize = NSSize(width: 720, height: 320)
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
        window.setContentSize(NSSize(width: 680, height: 680))
        window.minSize = NSSize(width: 680, height: 680)
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
    case resizeAutoTiledWindows
    case toggleFocusGroups
    case openSettings
}

private final class WindowBuddyHotKeyController {
    fileprivate static let signature: OSType = 0x57424459
    fileprivate typealias Handler = @MainActor (WindowBuddyHotKeyAction) -> Void

    private enum Identifier: UInt32 {
        case fillFrontmostWindowAndTemporarilyRemoveFromTiling = 1
        case restoreMostRecentlyRemovedWindowToTiling = 2
        case resizeAutoTiledWindows = 4
        case toggleFocusGroups = 6
        case openSettings = 8

        var action: WindowBuddyHotKeyAction {
            switch self {
            case .fillFrontmostWindowAndTemporarilyRemoveFromTiling:
                .fillFrontmostWindowAndTemporarilyRemoveFromTiling
            case .restoreMostRecentlyRemovedWindowToTiling:
                .restoreMostRecentlyRemovedWindowToTiling
            case .resizeAutoTiledWindows:
                .resizeAutoTiledWindows
            case .toggleFocusGroups:
                .toggleFocusGroups
            case .openSettings:
                .openSettings
            }
        }
    }

    private let handler: Handler
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            windowBuddyHotKeyCallback,
                            1,
                            &eventType,
                            userData,
                            &eventHandler)

        registerHotKey(keyCode: UInt32(kVK_UpArrow),
                       modifiers: UInt32(optionKey),
                       identifier: .fillFrontmostWindowAndTemporarilyRemoveFromTiling)
        registerHotKey(keyCode: UInt32(kVK_DownArrow),
                       modifiers: UInt32(optionKey),
                       identifier: .restoreMostRecentlyRemovedWindowToTiling)
        registerHotKey(keyCode: UInt32(kVK_ANSI_7),
                       modifiers: UInt32(cmdKey | shiftKey),
                       identifier: .resizeAutoTiledWindows)
        registerHotKey(keyCode: UInt32(kVK_ANSI_6),
                       modifiers: UInt32(cmdKey | shiftKey),
                       identifier: .toggleFocusGroups)
        registerHotKey(keyCode: UInt32(kVK_ANSI_8),
                       modifiers: UInt32(cmdKey | shiftKey),
                       identifier: .openSettings)
    }

    func stop() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys = []

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleHotKey(identifier: UInt32) {
        guard let identifier = Identifier(rawValue: identifier) else {
            return
        }

        Task { @MainActor in
            handler(identifier.action)
        }
    }

    private func registerHotKey(keyCode: UInt32,
                                modifiers: UInt32,
                                identifier: Identifier) {
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
            return
        }

        hotKeys.append(hotKey)
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
