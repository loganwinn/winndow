import AppKit
import ServiceManagement

// MARK: - Accessibility window access

func axScreens() -> [(frame: CGRect, visible: CGRect)] {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
    return NSScreen.screens.map { (flip($0.frame), flip($0.visibleFrame)) }
}

func focusedWindow() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    var w: CFTypeRef?
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &w) == .success, let w else { return nil }
    return (w as! AXUIElement)
}

func frame(of w: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?
    guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &origin)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

func setFrame(_ w: AXUIElement, _ r: CGRect) {
    // Apps with "enhanced UI" on (set by VoiceOver-aware tools) animate and fight resizes; turn it off around the move.
    var pid: pid_t = 0
    AXUIElementGetPid(w, &pid)
    let app = AXUIElementCreateApplication(pid)
    var enhanced: CFTypeRef?
    let wasEnhanced = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &enhanced) == .success
        && (enhanced as? Bool) == true
    if wasEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }

    var origin = r.origin, size = r.size
    let pos = AXValueCreate(.cgPoint, &origin)!, sz = AXValueCreate(.cgSize, &size)!
    // Size, move, size again: the first size can be clamped by the old screen when crossing displays.
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sz)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pos)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sz)

    if wasEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
}

// MARK: - Actions

var undoStack: [(AXUIElement, CGRect)] = []
var redoStack: [(AXUIElement, CGRect)] = []

func performAction(_ action: Action) {
    guard AXIsProcessTrusted() else { promptForAccessibility(); return }
    if action == .undo || action == .redo {
        var from = action == .undo ? undoStack : redoStack
        guard let (w, r) = from.popLast(), let current = frame(of: w) else { return }
        if action == .undo { undoStack = from; redoStack.append((w, current)) } else { redoStack = from; undoStack.append((w, current)) }
        setFrame(w, r)
        return
    }
    guard let w = focusedWindow(), let win = frame(of: w) else { NSSound.beep(); return }
    let screens = axScreens()
    guard !screens.isEmpty else { return }
    // The window's screen is the one it overlaps most.
    let i = screens.indices.max { a, b in
        let x = screens[a].frame.intersection(win), y = screens[b].frame.intersection(win)
        return (x.isNull ? 0 : x.width * x.height) < (y.isNull ? 0 : y.width * y.height)
    }!
    var dest: CGRect?
    if action == .nextDisplay || action == .previousDisplay {
        guard screens.count > 1 else { return }
        dest = screens[(i + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count].visible
    }
    guard let r = target(action, win: win, vf: screens[i].visible, dest: dest), r != win else { return }
    undoStack.append((w, win))
    if undoStack.count > 50 { undoStack.removeFirst() }
    redoStack.removeAll()
    setFrame(w, r)
}

func promptForAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    let accessItem = NSMenuItem(title: "⚠︎ Allow Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    let groups: [[Action]] = [
        [.center, .fullscreen],
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.upperLeft, .lowerLeft, .upperRight, .lowerRight],
        [.nextDisplay, .previousDisplay],
        [.nextThird, .previousThird],
        [.larger, .smaller],
        [.undo, .redo],
    ]
    lazy var editor = ShortcutsEditor(order: groups.flatMap { $0 }) { [weak self] in self?.buildMenu() }

    func applicationDidFinishLaunching(_ note: Notification) {
        if !AXIsProcessTrusted() { promptForAccessibility() }
        installHotkeyHandler()
        registerHotkeys()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Winndow")
        loginItem.target = self
        buildMenu()
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        accessItem.target = self
        menu.addItem(accessItem)
        for group in groups {
            for a in group {
                let s = shortcuts[a]
                let mi = NSMenuItem(title: a.title, action: #selector(run(_:)), keyEquivalent: s?.char ?? "")
                mi.keyEquivalentModifierMask = s?.mods ?? []
                mi.tag = actionsByID.firstIndex(of: a)!
                mi.target = self
                if failedActions.contains(a) { mi.title += " (shortcut taken by another app)" }
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }
        let edit = NSMenuItem(title: "Edit Shortcuts…", action: #selector(editShortcuts), keyEquivalent: ",")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit Winndow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        accessItem.isHidden = AXIsProcessTrusted()
    }

    @objc func openAccessibilitySettings() {
        promptForAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func run(_ sender: NSMenuItem) { performAction(actionsByID[sender.tag]) }

    @objc func editShortcuts() { editor.show() }

    // Clicking the Dock or Finder icon while Winndow is already running opens the shortcuts editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        editor.show()
        return false
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
