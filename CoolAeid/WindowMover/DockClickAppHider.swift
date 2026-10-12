//
//  DockClickAppHider.swift
//  WindowBuddy
//
//  Created by Claude on 12/10/2026.
//

import AppKit
import ApplicationServices

/// Clicking the Dock icon of the app that is already frontmost hides it.
/// Clicks on any other Dock item keep their standard behavior, and clicking a
/// hidden app's icon reveals it as usual.
///
/// The mouse-down on a matching icon is held back until the gesture is known:
/// a plain click hides the app, while a drag or a long press replays the
/// mouse-down so rearranging icons and the press-and-hold menu still work.
final class DockClickAppHider {
    private static let dockBundleIdentifier = "com.apple.dock"
    private static let applicationDockItemSubrole = "AXApplicationDockItem"
    private static let syntheticEventMarker: Int64 = 0x44_43_41_48
    // Larger than the biggest Dock tile with magnification, so only clicks
    // near the bottom, left or right screen edges are hit-tested.
    private static let dockEdgeBandThickness: CGFloat = 200
    private static let dragThreshold: CGFloat = 4
    private static let longPressDelay: TimeInterval = 0.35
    private static let accessibilityTimeout: Float = 0.1

    private struct PendingClick {
        let application: NSRunningApplication
        let location: CGPoint
        let longPressTimer: Timer
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dockApplication: NSRunningApplication?
    private var dockElement: AXUIElement?
    private var pendingClick: PendingClick?
    private var passesThroughUntilMouseUp = false

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else {
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                              place: .headInsertEventTap,
                                              options: .defaultTap,
                                              eventsOfInterest: eventMask,
                                              callback: dockClickAppHiderCallback,
                                              userInfo: userInfo) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let pendingClick {
            pendingClick.longPressTimer.invalidate()
            self.pendingClick = nil
        }
        passesThroughUntilMouseUp = false

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    fileprivate func handleEvent(type: CGEventType,
                                 event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            return handleMouseDragged(event)
        case .leftMouseUp:
            return handleMouseUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        cancelPendingClick()
        passesThroughUntilMouseUp = false

        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard event.flags.intersection(modifiers).isEmpty,
              let application = frontmostApplicationToHide(forClickAt: event.location) else {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        let longPressTimer = Timer(timeInterval: Self.longPressDelay, repeats: false) { [weak self] _ in
            self?.replayPendingMouseDown()
        }
        RunLoop.main.add(longPressTimer, forMode: .common)
        pendingClick = PendingClick(application: application,
                                    location: location,
                                    longPressTimer: longPressTimer)
        return nil
    }

    private func handleMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let pendingClick else {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        guard hypot(location.x - pendingClick.location.x,
                    location.y - pendingClick.location.y) > Self.dragThreshold else {
            return nil
        }

        // Turn this drag event into the held-back mouse-down and re-post the
        // drag behind it, so the Dock sees a normal drag start.
        cancelPendingClick()
        passesThroughUntilMouseUp = true
        if let drag = event.copy() {
            drag.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            DispatchQueue.main.async {
                drag.post(tap: .cgSessionEventTap)
            }
        }
        event.type = .leftMouseDown
        event.location = pendingClick.location
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if passesThroughUntilMouseUp {
            passesThroughUntilMouseUp = false
            return Unmanaged.passUnretained(event)
        }

        guard let pendingClick else {
            return Unmanaged.passUnretained(event)
        }

        cancelPendingClick()
        let application = pendingClick.application
        DispatchQueue.main.async {
            application.hide()
        }
        return nil
    }

    private func replayPendingMouseDown() {
        guard let pendingClick else {
            return
        }

        cancelPendingClick()
        passesThroughUntilMouseUp = true
        guard let mouseDown = CGEvent(mouseEventSource: nil,
                                      mouseType: .leftMouseDown,
                                      mouseCursorPosition: pendingClick.location,
                                      mouseButton: .left) else {
            passesThroughUntilMouseUp = false
            return
        }

        mouseDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        mouseDown.post(tap: .cgSessionEventTap)
    }

    private func cancelPendingClick() {
        pendingClick?.longPressTimer.invalidate()
        pendingClick = nil
    }

    private func frontmostApplicationToHide(forClickAt location: CGPoint) -> NSRunningApplication? {
        guard isNearDockEdge(location),
              AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication,
              !application.isHidden,
              application.activationPolicy == .regular,
              let applicationURL = application.bundleURL,
              let clickedURL = clickedApplicationDockItemURL(at: location),
              Self.normalizedPath(of: clickedURL) == Self.normalizedPath(of: applicationURL),
              hasOnScreenWindow(application) else {
            return nil
        }

        return application
    }

    private func isNearDockEdge(_ location: CGPoint) -> Bool {
        var displayID: CGDirectDisplayID = 0
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &displayID, &displayCount) == .success,
              displayCount > 0 else {
            return false
        }

        let bounds = CGDisplayBounds(displayID)
        return location.y >= bounds.maxY - Self.dockEdgeBandThickness ||
            location.x <= bounds.minX + Self.dockEdgeBandThickness ||
            location.x >= bounds.maxX - Self.dockEdgeBandThickness
    }

    private func clickedApplicationDockItemURL(at location: CGPoint) -> URL? {
        guard let dockElement = currentDockElement() else {
            return nil
        }

        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockElement,
                                               Float(location.x),
                                               Float(location.y),
                                               &hitElement) == .success,
              let hitElement,
              stringAttribute(kAXSubroleAttribute as CFString, for: hitElement) == Self.applicationDockItemSubrole else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hitElement, kAXURLAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFURLGetTypeID() else {
            return nil
        }

        return (value as! URL)
    }

    private func currentDockElement() -> AXUIElement? {
        if let dockApplication, !dockApplication.isTerminated, let dockElement {
            return dockElement
        }

        guard let dockApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.dockBundleIdentifier)
            .first else {
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockApplication.processIdentifier)
        // Keep a stalled Dock from holding up mouse input for the default 6 s.
        AXUIElementSetMessagingTimeout(dockElement, Self.accessibilityTimeout)
        self.dockApplication = dockApplication
        self.dockElement = dockElement
        return dockElement
    }

    /// An app without a window on screen keeps the standard Dock behavior,
    /// which reopens or reveals a window instead of hiding nothing.
    private func hasOnScreenWindow(_ application: NSRunningApplication) -> Bool {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                          kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windowInfo.contains { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == application.processIdentifier &&
                (window[kCGWindowLayer as String] as? Int) == 0 &&
                ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0
        }
    }

    private func stringAttribute(_ attribute: CFString, for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private static func normalizedPath(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private let dockClickAppHiderCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let hider = Unmanaged<DockClickAppHider>.fromOpaque(userInfo).takeUnretainedValue()
    return hider.handleEvent(type: type, event: event)
}
