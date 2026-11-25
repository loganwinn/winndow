import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Shortcuts (Spectacle's defaults)

struct Shortcut { let key: Int; let mods: NSEvent.ModifierFlags }

let shortcuts: [Action: Shortcut] = [
    .center: .init(key: kVK_ANSI_C, mods: [.option, .command]),
    .fullscreen: .init(key: kVK_ANSI_F, mods: [.option, .command]),
    .leftHalf: .init(key: kVK_LeftArrow, mods: [.option, .command]),
    .rightHalf: .init(key: kVK_RightArrow, mods: [.option, .command]),
    .topHalf: .init(key: kVK_UpArrow, mods: [.option, .command]),
    .bottomHalf: .init(key: kVK_DownArrow, mods: [.option, .command]),
    .upperLeft: .init(key: kVK_LeftArrow, mods: [.control, .command]),
    .lowerLeft: .init(key: kVK_LeftArrow, mods: [.control, .shift, .command]),
    .upperRight: .init(key: kVK_RightArrow, mods: [.control, .command]),
    .lowerRight: .init(key: kVK_RightArrow, mods: [.control, .shift, .command]),
    .nextDisplay: .init(key: kVK_RightArrow, mods: [.control, .option, .command]),
    .previousDisplay: .init(key: kVK_LeftArrow, mods: [.control, .option, .command]),
    .nextThird: .init(key: kVK_RightArrow, mods: [.control, .option]),
    .previousThird: .init(key: kVK_LeftArrow, mods: [.control, .option]),
    .larger: .init(key: kVK_RightArrow, mods: [.control, .option, .shift]),
    .smaller: .init(key: kVK_LeftArrow, mods: [.control, .option, .shift]),
    .undo: .init(key: kVK_ANSI_Z, mods: [.option, .command]),
    .redo: .init(key: kVK_ANSI_Z, mods: [.option, .shift, .command]),
]

func carbonMods(_ m: NSEvent.ModifierFlags) -> UInt32 {
    var r: UInt32 = 0
    if m.contains(.command) { r |= UInt32(cmdKey) }
    if m.contains(.option) { r |= UInt32(optionKey) }
    if m.contains(.control) { r |= UInt32(controlKey) }
    if m.contains(.shift) { r |= UInt32(shiftKey) }
    return r
}

func keyEquivalent(_ key: Int) -> String {
    let arrows = [kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
                  kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey]
    if let a = arrows[key] { return String(Character(UnicodeScalar(a)!)) }
    return [kVK_ANSI_C: "c", kVK_ANSI_F: "f", kVK_ANSI_Z: "z"][key] ?? ""
}

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

// MARK: - Global hotkeys (Carbon, needs no extra permission)

let actionsByID = Action.allCases
func registerHotkeys() -> [Action] {
    var failed: [Action] = []
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        performAction(actionsByID[Int(id.id)])
        return noErr
    }, 1, &spec, nil, nil)
    for (n, action) in actionsByID.enumerated() {
        guard let s = shortcuts[action] else { continue }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x57494E44), id: UInt32(n)) // 'WIND'
        if RegisterEventHotKey(UInt32(s.key), carbonMods(s.mods), id, GetApplicationEventTarget(), 0, &ref) != noErr {
            failed.append(action)
        }
    }
    return failed
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        if !AXIsProcessTrusted() { promptForAccessibility() }
        let failed = registerHotkeys()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Winndow")
        let menu = NSMenu()
        menu.delegate = self
        let groups: [[Action]] = [
            [.center, .fullscreen],
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            [.upperLeft, .lowerLeft, .upperRight, .lowerRight],
            [.nextDisplay, .previousDisplay],
            [.nextThird, .previousThird],
            [.larger, .smaller],
            [.undo, .redo],
        ]
        for group in groups {
            for a in group {
                let s = shortcuts[a]!
                let mi = NSMenuItem(title: a.title, action: #selector(run(_:)), keyEquivalent: keyEquivalent(s.key))
                mi.keyEquivalentModifierMask = s.mods
                mi.tag = actionsByID.firstIndex(of: a)!
                mi.target = self
                if failed.contains(a) { mi.title += " (shortcut taken by another app)" }
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit Winndow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func run(_ sender: NSMenuItem) { performAction(actionsByID[sender.tag]) }

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
