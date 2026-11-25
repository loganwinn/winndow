import CoreGraphics

// Run with: ./build.sh test
let vf = CGRect(x: 0, y: 25, width: 1920, height: 1055)
let win = CGRect(x: 300, y: 200, width: 800, height: 600)

let half = target(.leftHalf, win: win, vf: vf)!
assert(half == CGRect(x: 0, y: 25, width: 960, height: 1055), "left half \(half)")
let twoThirds = target(.leftHalf, win: half, vf: vf)!
assert(twoThirds.width == 1280, "second press -> 2/3 \(twoThirds)")
let oneThird = target(.leftHalf, win: twoThirds, vf: vf)!
assert(oneThird.width == 640, "third press -> 1/3 \(oneThird)")
assert(target(.leftHalf, win: oneThird, vf: vf)!.width == 960, "fourth press -> back to 1/2")

let right = target(.rightHalf, win: win, vf: vf)!
assert(right.maxX == vf.maxX && right.width == 960, "right half \(right)")
let bottom = target(.bottomHalf, win: win, vf: vf)!
assert(bottom.maxY == vf.maxY && bottom.height == 527, "bottom half \(bottom)")
let lr = target(.lowerRight, win: win, vf: vf)!
assert(lr.maxX == vf.maxX && lr.maxY == vf.maxY && lr.width == 960, "lower right \(lr)")
let ul = target(.upperLeft, win: win, vf: vf)!
assert(ul.origin == vf.origin && ul.height == 527, "upper left \(ul)")

assert(target(.fullscreen, win: win, vf: vf)! == vf)
let c = target(.center, win: win, vf: vf)!
assert(c.size == win.size && abs(c.midX - vf.midX) <= 1 && abs(c.midY - vf.midY) <= 1, "center \(c)")

let t = thirds(vf)
assert(target(.nextThird, win: win, vf: vf)! == t[0], "not in a third -> first")
assert(target(.nextThird, win: t[0], vf: vf)! == t[1])
assert(target(.previousThird, win: t[0], vf: vf)! == t[5], "wraps backwards")

let bigger = target(.larger, win: win, vf: vf)!
assert(bigger.width == 830 && bigger.height == 630, "larger \(bigger)")
let smaller = target(.smaller, win: win, vf: vf)!
assert(smaller.width == 770, "smaller \(smaller)")
assert(target(.smaller, win: CGRect(x: 0, y: 0, width: 490, height: 300), vf: vf)!.width == 490, "won't shrink below a quarter")
assert(target(.larger, win: vf, vf: vf)! == vf, "fullscreen stays fullscreen")
let fromFull = target(.smaller, win: vf, vf: vf)!
assert(fromFull.width == vf.width - 30 && abs(fromFull.midX - vf.midX) <= 1, "shrink from fullscreen around center \(fromFull)")

let second = CGRect(x: 1920, y: 0, width: 1280, height: 800)
let moved = target(.nextDisplay, win: win, vf: vf, dest: second)!
assert(second.contains(moved) && moved.size == win.size, "next display centers \(moved)")
assert(target(.nextDisplay, win: vf, vf: vf, dest: second)! == second, "too big -> fill dest")

print("LayoutCheck: all passed")
