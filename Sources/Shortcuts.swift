import AppKit
import Carbon.HIToolbox

// MARK: - Model and storage

struct Shortcut: Equatable {
    var key: Int
    var mods: NSEvent.ModifierFlags
    var char: String // menu key equivalent, captured when recorded
    static func == (a: Shortcut, b: Shortcut) -> Bool { a.key == b.key && a.mods == b.mods }
}

private func S(_ key: Int, _ mods: NSEvent.ModifierFlags) -> Shortcut {
    let arrows = [kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
                  kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey]
    let char = arrows[key].map { String(Character(UnicodeScalar($0)!)) }
        ?? [kVK_ANSI_C: "c", kVK_ANSI_F: "f", kVK_ANSI_Z: "z"][key] ?? ""
    return Shortcut(key: key, mods: mods, char: char)
}

/// Spectacle's defaults.
let defaultShortcuts: [Action: Shortcut] = [
    .center: S(kVK_ANSI_C, [.option, .command]),
    .fullscreen: S(kVK_ANSI_F, [.option, .command]),
    .leftHalf: S(kVK_LeftArrow, [.option, .command]),
    .rightHalf: S(kVK_RightArrow, [.option, .command]),
    .topHalf: S(kVK_UpArrow, [.option, .command]),
    .bottomHalf: S(kVK_DownArrow, [.option, .command]),
    .upperLeft: S(kVK_LeftArrow, [.control, .command]),
    .lowerLeft: S(kVK_LeftArrow, [.control, .shift, .command]),
    .upperRight: S(kVK_RightArrow, [.control, .command]),
    .lowerRight: S(kVK_RightArrow, [.control, .shift, .command]),
    .nextDisplay: S(kVK_RightArrow, [.control, .option, .command]),
    .previousDisplay: S(kVK_LeftArrow, [.control, .option, .command]),
    .nextThird: S(kVK_RightArrow, [.control, .option]),
    .previousThird: S(kVK_LeftArrow, [.control, .option]),
    .larger: S(kVK_RightArrow, [.control, .option, .shift]),
    .smaller: S(kVK_LeftArrow, [.control, .option, .shift]),
    .undo: S(kVK_ANSI_Z, [.option, .command]),
    .redo: S(kVK_ANSI_Z, [.option, .shift, .command]),
]

private let storeKey = "shortcuts" // [action: "key|mods|char"], "" = no shortcut

/// Current shortcuts; a missing entry means the action has no shortcut.
var shortcuts: [Action: Shortcut] = {
    var r = defaultShortcuts
    for (name, v) in UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String] ?? [:] {
        guard let a = Action(rawValue: name) else { continue }
        let p = v.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        if p.count == 3, let k = Int(p[0]), let m = UInt(p[1]) {
            r[a] = Shortcut(key: k, mods: NSEvent.ModifierFlags(rawValue: m), char: String(p[2]))
        } else { r[a] = nil }
    }
    return r
}()

func saveShortcuts() {
    var d: [String: String] = [:]
    for a in Action.allCases {
        d[a.rawValue] = shortcuts[a].map { "\($0.key)|\($0.mods.rawValue)|\($0.char)" } ?? ""
    }
    UserDefaults.standard.set(d, forKey: storeKey)
}

func display(_ s: Shortcut?) -> String {
    guard let s else { return "None" }
    var r = ""
    if s.mods.contains(.control) { r += "⌃" }
    if s.mods.contains(.option) { r += "⌥" }
    if s.mods.contains(.shift) { r += "⇧" }
    if s.mods.contains(.command) { r += "⌘" }
    let names: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
    return r + (names[s.key] ?? s.char.uppercased())
}

// MARK: - Global hotkeys (Carbon, needs no extra permission)

let actionsByID = Action.allCases
private var hotKeyRefs: [EventHotKeyRef] = []
var failedActions: Set<Action> = []

func installHotkeyHandler() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        performAction(actionsByID[Int(id.id)])
        return noErr
    }, 1, &spec, nil, nil)
}

func unregisterHotkeys() {
    hotKeyRefs.forEach { UnregisterEventHotKey($0) }
    hotKeyRefs.removeAll()
    failedActions.removeAll()
}

func registerHotkeys() {
    unregisterHotkeys()
    func carbon(_ m: NSEvent.ModifierFlags) -> UInt32 {
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.option) { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        if m.contains(.shift) { r |= UInt32(shiftKey) }
        return r
    }
    for (n, action) in actionsByID.enumerated() {
        guard let s = shortcuts[action] else { continue }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x57494E44), id: UInt32(n)) // 'WIND'
        if RegisterEventHotKey(UInt32(s.key), carbon(s.mods), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            hotKeyRefs.append(ref)
        } else {
            failedActions.insert(action)
        }
    }
}

// MARK: - Shortcuts editor window

final class ShortcutsEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var buttons: [Action: NSButton] = [:]
    private var recording: Action?
    private var monitor: Any?
    private let onChange: () -> Void

    init(order: [Action], onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 6
        grid.columnSpacing = 16
        for a in order {
            let b = NSButton(title: "", target: self, action: #selector(record(_:)))
            b.bezelStyle = .rounded
            b.tag = actionsByID.firstIndex(of: a)!
            b.widthAnchor.constraint(equalToConstant: 170).isActive = true
            b.setAccessibilityLabel("\(a.title) shortcut")
            buttons[a] = b
            grid.addRow(with: [NSTextField(labelWithString: a.title), b])
        }
        grid.column(at: 0).xPlacement = .trailing

        let hint = NSTextField(wrappingLabelWithString: "Click a shortcut, then press the new keys. Delete removes it, Esc cancels. Use at least one of ⌘, ⌥ or ⌃.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let reset = NSButton(title: "Restore Spectacle Defaults", target: self, action: #selector(restoreDefaults))

        let stack = NSStackView(views: [grid, hint, reset])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        hint.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true

        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Winndow Shortcuts"
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        for (a, b) in buttons {
            b.title = a == recording ? "Press keys…" : display(shortcuts[a]) + (failedActions.contains(a) ? "  ⚠︎ in use" : "")
            b.toolTip = failedActions.contains(a) ? "Another app already uses this shortcut." : nil
        }
    }

    @objc private func record(_ sender: NSButton) {
        if recording != nil { stopRecording() }
        recording = actionsByID[sender.tag]
        unregisterHotkeys() // so the keys being recorded reach this window instead of firing actions
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e)
            return nil
        }
        refresh()
    }

    private func handle(_ e: NSEvent) {
        guard let a = recording else { return }
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = Int(e.keyCode)
        if key == kVK_Escape && mods.isEmpty { return stopRecording() }
        if (key == kVK_Delete || key == kVK_ForwardDelete) && mods.isEmpty {
            shortcuts[a] = nil
            saveShortcuts()
            return stopRecording()
        }
        // A plain or shift-only key would hijack normal typing everywhere.
        guard !mods.isDisjoint(with: [.command, .option, .control]) else { return NSSound.beep() }
        let s = Shortcut(key: key, mods: mods, char: e.characters(byApplyingModifiers: [])?.lowercased() ?? "")
        for (other, o) in shortcuts where other != a && o == s { shortcuts[other] = nil } // one action per shortcut
        shortcuts[a] = s
        saveShortcuts()
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        registerHotkeys()
        refresh()
        onChange()
    }

    @objc private func restoreDefaults() {
        if recording != nil { stopRecording() }
        shortcuts = defaultShortcuts
        saveShortcuts()
        registerHotkeys()
        refresh()
        onChange()
    }

    func windowWillClose(_ notification: Notification) {
        if recording != nil { stopRecording() }
    }
}
