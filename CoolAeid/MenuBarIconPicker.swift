import AppKit
import SwiftUI

@MainActor
final class MenuBarIconPickerWindowPresenter {
    private var windowController: NSWindowController?

    func show(selectedIconName: String, onSelect: @escaping (String) -> Void) {
        let view = MenuBarIconPickerView(selectedIconName: selectedIconName, onSelect: onSelect)

        if let windowController,
           let hostingController = windowController.contentViewController as? NSHostingController<MenuBarIconPickerView> {
            hostingController.rootView = view
            show(windowController)
            return
        }

        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Menu Bar Icon"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 480))
        window.minSize = NSSize(width: 360, height: 380)
        window.level = .floating

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        show(windowController)
    }

    private func show(_ windowController: NSWindowController) {
        NSApp.activate()
        windowController.showWindow(nil)
        windowController.window?.center()
        windowController.window?.makeKeyAndOrderFront(nil)
    }
}

private struct MenuBarIconPickerView: View {
    let selectedIconName: String
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var draftIconName: String

    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 92), spacing: 8)
    ]

    init(selectedIconName: String, onSelect: @escaping (String) -> Void) {
        self.selectedIconName = selectedIconName
        self.onSelect = onSelect
        _draftIconName = State(initialValue: selectedIconName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                currentPreview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu bar icon")
                        .font(.system(size: 14, weight: .semibold))
                    TextField("SF Symbol name", text: $draftIconName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .onSubmit(applyDraftIcon)
                }
            }

            HStack(spacing: 8) {
                Button(action: applyDraftIcon) {
                    Label("Apply", systemImage: "checkmark")
                }
                .disabled(!isValidSymbol(draftIconName))

                Button(action: resetIcon) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Spacer()

                Button(action: openSFSymbolsGallery) {
                    Label("Gallery", systemImage: "safari")
                }
            }
            .controlSize(.small)

            searchField

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredOptions) { option in
                        MenuBarIconTile(
                            option: option,
                            isSelected: option.name == draftIconName,
                            select: {
                                draftIconName = option.name
                                onSelect(option.name)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var currentPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            Image(systemName: isValidSymbol(draftIconName) ? draftIconName : "questionmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 58, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search icons", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var filteredOptions: [MenuBarIconOption] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return MenuBarIconCatalog.availableOptions
        }

        return MenuBarIconCatalog.availableOptions.filter { option in
            option.matches(trimmedQuery)
        }
    }

    private func applyDraftIcon() {
        let trimmedIconName = draftIconName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSymbol(trimmedIconName) else {
            NSSound.beep()
            return
        }

        draftIconName = trimmedIconName
        onSelect(trimmedIconName)
    }

    private func resetIcon() {
        draftIconName = "pip"
        onSelect("pip")
    }

    private func openSFSymbolsGallery() {
        guard let url = URL(string: "https://developer.apple.com/sf-symbols/") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func isValidSymbol(_ iconName: String) -> Bool {
        let trimmedIconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSImage(systemSymbolName: trimmedIconName, accessibilityDescription: nil) != nil
    }
}

private struct MenuBarIconTile: View {
    let option: MenuBarIconOption
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                Image(systemName: option.name)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 28, height: 28)
                Text(option.shortName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(tileBackground)
            .overlay(tileBorder)
        }
        .buttonStyle(.plain)
        .help(option.name)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
    }
}

private struct MenuBarIconOption: Identifiable {
    let name: String
    let category: String
    let aliases: [String]

    var id: String { name }

    var shortName: String {
        name
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".circle", with: "")
            .replacingOccurrences(of: ".square", with: "")
    }

    var isAvailable: Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.lowercased()
        return name.localizedCaseInsensitiveContains(normalizedQuery)
            || category.localizedCaseInsensitiveContains(normalizedQuery)
            || aliases.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }
}

private enum MenuBarIconCatalog {
    static let availableOptions = allOptions.filter(\.isAvailable)

    private static let allOptions: [MenuBarIconOption] = [
        option("pip", "PiP", "picture", "video", "window"),
        option("pip.fill", "PiP", "picture", "video", "window"),
        option("pip.enter", "PiP", "enter", "start", "video"),
        option("pip.exit", "PiP", "exit", "stop", "video"),
        option("play.rectangle", "Media", "video", "watch", "pip"),
        option("play.rectangle.fill", "Media", "video", "watch", "pip"),
        option("rectangle.inset.filled", "Windows", "focus", "frame", "layout"),
        option("rectangle.on.rectangle", "Windows", "stack", "copy", "pip"),
        option("rectangle.on.rectangle.circle", "Windows", "stack", "copy", "pip"),
        option("macwindow", "Windows", "app", "screen", "desktop"),
        option("macwindow.on.rectangle", "Windows", "app", "screen", "desktop"),
        option("menubar.rectangle", "Windows", "menu", "bar", "status"),
        option("rectangle.3.group", "Windows", "layout", "windowbuddy", "tile"),
        option("rectangle.grid.2x2", "Windows", "grid", "tile", "layout"),
        option("square.grid.2x2", "Windows", "grid", "tile", "apps"),
        option("dock.rectangle", "Dock", "dockmover", "dock", "apps"),
        option("app.dashed", "Apps", "application", "placeholder", "bundle"),
        option("app.badge", "Apps", "application", "bundle", "badge"),
        option("apps.iphone", "Apps", "application", "stack", "mobile"),
        option("display", "Display", "screen", "monitor", "desktop"),
        option("display.2", "Display", "screen", "monitor", "desktop"),
        option("desktopcomputer", "Display", "screen", "monitor", "mac"),
        option("laptopcomputer", "Display", "screen", "macbook", "portable"),
        option("visionpro", "Display", "spatial", "screen", "viewer"),
        option("camera", "Media", "capture", "record", "screen"),
        option("camera.fill", "Media", "capture", "record", "screen"),
        option("video", "Media", "camera", "record", "pip"),
        option("video.fill", "Media", "camera", "record", "pip"),
        option("record.circle", "Media", "capture", "record", "screen"),
        option("record.circle.fill", "Media", "capture", "record", "screen"),
        option("eye", "Visibility", "view", "watch", "glance"),
        option("eye.fill", "Visibility", "view", "watch", "glance"),
        option("eye.circle", "Visibility", "view", "watch", "glance"),
        option("eye.slash", "Visibility", "hide", "private", "glance"),
        option("cursorarrow", "Pointer", "mouse", "pointer", "select"),
        option("cursorarrow.motionlines", "Pointer", "mouse", "pointer", "switch"),
        option("cursorarrow.click", "Pointer", "mouse", "click", "select"),
        option("point.topleft.down.curvedto.point.bottomright.up", "Pointer", "drag", "move", "resize"),
        option("arrow.up.left.and.arrow.down.right", "Windows", "resize", "expand", "glance"),
        option("arrow.down.right.and.arrow.up.left", "Windows", "resize", "collapse", "glance"),
        option("arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "Windows", "resize", "fullscreen", "tile"),
        option("arrow.triangle.2.circlepath", "Action", "refresh", "cycle", "reload"),
        option("arrow.clockwise", "Action", "refresh", "reload", "sync"),
        option("arrow.counterclockwise", "Action", "undo", "reset", "back"),
        option("bolt", "Action", "fast", "instant", "power"),
        option("bolt.fill", "Action", "fast", "instant", "power"),
        option("bolt.circle", "Action", "fast", "instant", "power"),
        option("sparkles", "Style", "magic", "new", "icon"),
        option("wand.and.stars", "Style", "magic", "auto", "icon"),
        option("star", "Style", "favorite", "main", "focus"),
        option("star.fill", "Style", "favorite", "main", "focus"),
        option("circle.hexagongrid", "Style", "grid", "cluster", "apps"),
        option("circle.grid.3x3", "Style", "grid", "launcher", "apps"),
        option("square.stack.3d.up", "Windows", "stack", "layers", "apps"),
        option("square.stack.3d.up.fill", "Windows", "stack", "layers", "apps"),
        option("square.on.square", "Windows", "copy", "stack", "pip"),
        option("square.on.square.dashed", "Windows", "copy", "stack", "placeholder"),
        option("square.dashed", "Dock", "placeholder", "empty", "slot"),
        option("pin", "Dock", "pin", "keep", "dock"),
        option("pin.fill", "Dock", "pin", "keep", "dock"),
        option("keyboard", "Shortcuts", "hotkey", "command", "input"),
        option("command", "Shortcuts", "hotkey", "keyboard", "shortcut"),
        option("option", "Shortcuts", "hotkey", "keyboard", "shortcut"),
        option("control", "Shortcuts", "hotkey", "keyboard", "shortcut"),
        option("shift", "Shortcuts", "hotkey", "keyboard", "shortcut"),
        option("space", "Shortcuts", "hotkey", "keyboard", "shortcut"),
        option("escape", "Shortcuts", "hotkey", "keyboard", "shortcut"),
        option("slider.horizontal.3", "Settings", "controls", "preferences", "adjust"),
        option("switch.2", "Settings", "toggle", "controls", "preferences"),
        option("gearshape", "Settings", "preferences", "settings", "controls"),
        option("gearshape.fill", "Settings", "preferences", "settings", "controls"),
        option("gearshape.2", "Settings", "preferences", "settings", "controls"),
        option("power", "Action", "quit", "stop", "off"),
        option("pause", "Media", "stop", "pause", "hold"),
        option("playpause", "Media", "start", "stop", "toggle"),
        option("checkmark.circle", "Status", "ready", "allowed", "ok"),
        option("checkmark.circle.fill", "Status", "ready", "allowed", "ok"),
        option("exclamationmark.circle", "Status", "warning", "permission", "attention"),
        option("lock.shield", "Status", "permission", "security", "privacy"),
        option("lock.shield.fill", "Status", "permission", "security", "privacy"),
        option("shield", "Status", "permission", "security", "privacy"),
        option("shield.fill", "Status", "permission", "security", "privacy"),
        option("person.crop.rectangle.stack", "Apps", "people", "window", "stack"),
        option("person.crop.square", "Apps", "profile", "app", "window"),
        option("bubble.left.and.bubble.right", "Communication", "chat", "messages", "talk"),
        option("message", "Communication", "chat", "messages", "talk"),
        option("waveform", "Audio", "sound", "voice", "activity"),
        option("waveform.circle", "Audio", "sound", "voice", "activity"),
        option("speaker.wave.2", "Audio", "sound", "volume", "media"),
        option("mic", "Audio", "sound", "voice", "record"),
        option("paintbrush", "Style", "design", "theme", "icon"),
        option("paintpalette", "Style", "design", "theme", "icon"),
        option("safari", "Browser", "web", "internet", "browse"),
        option("globe", "Browser", "web", "internet", "network"),
        option("network", "Browser", "web", "internet", "network"),
        option("magnifyingglass", "Search", "find", "lookup", "browse"),
        option("line.3.horizontal", "Menu", "list", "menu", "hamburger"),
        option("ellipsis", "Menu", "more", "options", "menu"),
        option("ellipsis.circle", "Menu", "more", "options", "menu"),
        option("plus.circle", "Action", "add", "new", "select"),
        option("minus.circle", "Action", "remove", "delete", "hide"),
        option("xmark.circle", "Action", "close", "remove", "stop"),
        option("xmark.circle.fill", "Action", "close", "remove", "stop")
    ]

    private static func option(_ name: String, _ category: String, _ aliases: String...) -> MenuBarIconOption {
        MenuBarIconOption(name: name, category: category, aliases: aliases)
    }
}
