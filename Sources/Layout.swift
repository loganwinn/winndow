import CoreGraphics

// Pure window geometry, modeled on Spectacle's bundled "Window Position Calculations".
// All rects are in Accessibility space: origin at the top-left of the primary display, y grows down.

enum Action: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case upperLeft, upperRight, lowerLeft, lowerRight
    case fullscreen, center
    case nextThird, previousThird
    case larger, smaller
    case nextDisplay, previousDisplay
    case undo, redo

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .upperLeft: return "Upper Left"
        case .upperRight: return "Upper Right"
        case .lowerLeft: return "Lower Left"
        case .lowerRight: return "Lower Right"
        case .fullscreen: return "Fullscreen"
        case .center: return "Center"
        case .nextThird: return "Next Third"
        case .previousThird: return "Previous Third"
        case .larger: return "Make Larger"
        case .smaller: return "Make Smaller"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        case .undo: return "Undo"
        case .redo: return "Redo"
        }
    }
}

/// Spectacle's "rect centered within rect": candidate contains the window and their centers match within a pixel or two.
func centered(_ candidate: CGRect, _ win: CGRect, tolerance t: CGFloat = 2) -> Bool {
    candidate.insetBy(dx: -t, dy: -t).contains(win)
        && abs(candidate.midX - win.midX) <= t
        && abs(candidate.midY - win.midY) <= t
}

/// Repeat presses cycle 1/2 -> 2/3 -> 1/3 -> 1/2, like Spectacle.
private func cycle(_ win: CGRect, _ make: (CGFloat) -> CGRect) -> CGRect {
    let sizes: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
    for i in 0..<(sizes.count - 1) where centered(make(sizes[i]), win) { return make(sizes[i + 1]) }
    return make(sizes[0])
}

private func fl(_ v: CGFloat) -> CGFloat { v.rounded(.down) }

func thirds(_ vf: CGRect) -> [CGRect] {
    let w = fl(vf.width / 3), h = fl(vf.height / 3)
    let cols = (0..<3).map { CGRect(x: vf.minX + w * CGFloat($0), y: vf.minY, width: w, height: vf.height) }
    let rows = (0..<3).map { CGRect(x: vf.minX, y: vf.minY + h * CGFloat($0), width: vf.width, height: h) }
    return cols + rows
}

func centerRect(_ win: CGRect, in vf: CGRect) -> CGRect {
    CGRect(x: vf.minX + fl(vf.width / 2) - fl(win.width / 2),
           y: vf.minY + fl(vf.height / 2) - fl(win.height / 2),
           width: win.width, height: win.height)
}

/// Grow (positive) or shrink (negative) by `offset`, sticking to screen edges the window touches.
func resize(_ win: CGRect, in vf: CGRect, by offset: CGFloat) -> CGRect {
    func touching(_ gap: CGFloat) -> Bool { abs(gap) <= 5 }
    let left = touching(win.minX - vf.minX), right = touching(win.maxX - vf.maxX)
    let top = touching(win.minY - vf.minY), bottom = touching(win.maxY - vf.maxY)
    var r = win

    r.size.width += offset
    r.origin.x -= fl(offset / 2)
    if right { r.origin.x = vf.maxX - r.width; if left { r.size.width = vf.width } }
    if left { r.origin.x = vf.minX }
    if r.width >= vf.width { r.size.width = vf.width; r.origin.x = vf.minX }

    r.size.height += offset
    r.origin.y -= fl(offset / 2)
    if bottom { r.origin.y = vf.maxY - r.height; if top { r.size.height = vf.height } }
    if top { r.origin.y = vf.minY }
    if r.height >= vf.height { r.size.height = vf.height; r.origin.y = vf.minY }

    if left && right && top && bottom && offset < 0 { r = win.insetBy(dx: -offset / 2, dy: -offset / 2) }
    if r.width <= fl(vf.width / 4) || r.height <= fl(vf.height / 4) { return win }
    return r
}

/// Where a window should go for `action`. `vf` is the visible frame of the window's screen,
/// `dest` the visible frame of the target screen (only differs for next/previous display).
func target(_ action: Action, win: CGRect, vf: CGRect, dest: CGRect? = nil) -> CGRect? {
    let halfH = fl(vf.height / 2)
    switch action {
    case .leftHalf:
        return cycle(win) { CGRect(x: vf.minX, y: vf.minY, width: fl(vf.width * $0), height: vf.height) }
    case .rightHalf:
        return cycle(win) { let w = fl(vf.width * $0); return CGRect(x: vf.maxX - w, y: vf.minY, width: w, height: vf.height) }
    case .topHalf:
        return cycle(win) { CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: fl(vf.height * $0)) }
    case .bottomHalf:
        return cycle(win) { let h = fl(vf.height * $0); return CGRect(x: vf.minX, y: vf.maxY - h, width: vf.width, height: h) }
    case .upperLeft:
        return cycle(win) { CGRect(x: vf.minX, y: vf.minY, width: fl(vf.width * $0), height: halfH) }
    case .upperRight:
        return cycle(win) { let w = fl(vf.width * $0); return CGRect(x: vf.maxX - w, y: vf.minY, width: w, height: halfH) }
    case .lowerLeft:
        return cycle(win) { CGRect(x: vf.minX, y: vf.maxY - halfH, width: fl(vf.width * $0), height: halfH) }
    case .lowerRight:
        return cycle(win) { let w = fl(vf.width * $0); return CGRect(x: vf.maxX - w, y: vf.maxY - halfH, width: w, height: halfH) }
    case .fullscreen:
        return vf
    case .center:
        return centerRect(win, in: vf)
    case .nextThird, .previousThird:
        let t = thirds(vf)
        guard let i = t.firstIndex(where: { centered($0, win) }) else { return t[0] }
        return t[(i + (action == .nextThird ? 1 : t.count - 1)) % t.count]
    case .larger:
        return resize(win, in: vf, by: 30)
    case .smaller:
        return resize(win, in: vf, by: -30)
    case .nextDisplay, .previousDisplay:
        guard let d = dest else { return nil }
        return (win.width <= d.width && win.height <= d.height) ? centerRect(win, in: d) : d
    case .undo, .redo:
        return nil
    }
}
