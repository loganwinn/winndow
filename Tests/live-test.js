// Live end-to-end test: presses Winndow's real shortcuts on a TextEdit window and checks where it lands.
// Run: osascript -l JavaScript Tests/live-test.js   (Winndow running, Spectacle quit, single display)
ObjC.import("AppKit")
const se = Application("System Events")
const te = Application("TextEdit")
te.activate()
te.documents.push(te.Document())
delay(1)

const scr = $.NSScreen.screens.js[0]
const H = scr.frame.size.height, v = scr.visibleFrame
const vf = { x: v.origin.x, y: H - v.origin.y - v.size.height, w: v.size.width, h: v.size.height }
const fl = Math.floor, hh = fl(vf.h / 2), w3 = fl(vf.w / 3), h3 = fl(vf.h / 3)

const frame = () => { const b = te.windows[0].bounds(); return [b.x, b.y, b.width, b.height] }
const setFrame = (x, y, w, h) => { te.windows[0].bounds = { x, y, width: w, height: h }; delay(0.3) }
const M = { cmd: "command down", opt: "option down", ctrl: "control down", shift: "shift down" }
const press = (code, ...mods) => { se.keyCode(code, { using: mods.map(m => M[m]) }); delay(0.6) }
const L = 123, R = 124, D = 125, U = 126, C = 8, F = 3, Z = 6

let pass = 0, fail = 0
function check(name, want) {
  const got = frame()
  const ok = got.every((g, i) => Math.abs(g - want[i]) <= 2)
  ok ? pass++ : fail++
  console.log(`${ok ? "PASS" : "FAIL"} ${name}: got ${got} want ${want}`)
}

setFrame(200, 200, 800, 500)
press(L, "opt", "cmd"); check("left half", [vf.x, vf.y, fl(vf.w / 2), vf.h])
press(L, "opt", "cmd"); check("left 2/3", [vf.x, vf.y, fl(vf.w * 2 / 3), vf.h])
press(L, "opt", "cmd"); check("left 1/3", [vf.x, vf.y, fl(vf.w / 3), vf.h])
press(R, "opt", "cmd"); check("right half", [vf.x + vf.w - fl(vf.w / 2), vf.y, fl(vf.w / 2), vf.h])
press(U, "opt", "cmd"); check("top half", [vf.x, vf.y, vf.w, hh])
press(D, "opt", "cmd"); check("bottom half", [vf.x, vf.y + vf.h - hh, vf.w, hh])
press(L, "ctrl", "cmd"); check("upper left", [vf.x, vf.y, fl(vf.w / 2), hh])
press(L, "ctrl", "shift", "cmd"); check("lower left", [vf.x, vf.y + vf.h - hh, fl(vf.w / 2), hh])
press(R, "ctrl", "cmd"); check("upper right", [vf.x + vf.w - fl(vf.w / 2), vf.y, fl(vf.w / 2), hh])
press(R, "ctrl", "shift", "cmd"); check("lower right", [vf.x + vf.w - fl(vf.w / 2), vf.y + vf.h - hh, fl(vf.w / 2), hh])
press(F, "opt", "cmd"); check("fullscreen", [vf.x, vf.y, vf.w, vf.h])
press(L, "ctrl", "opt", "shift"); check("smaller", [vf.x + 15, vf.y + 15, vf.w - 30, vf.h - 30])
press(R, "ctrl", "opt", "shift"); check("larger", [vf.x, vf.y, vf.w, vf.h])
setFrame(200, 200, 800, 500)
press(C, "opt", "cmd"); check("center", [vf.x + fl(vf.w / 2) - 400, vf.y + fl(vf.h / 2) - 250, 800, 500])
press(R, "ctrl", "opt"); check("next third (1st)", [vf.x, vf.y, w3, vf.h])
press(R, "ctrl", "opt"); check("next third (2nd)", [vf.x + w3, vf.y, w3, vf.h])
press(L, "ctrl", "opt"); check("previous third", [vf.x, vf.y, w3, vf.h])
press(L, "ctrl", "opt"); check("previous third wraps", [vf.x, vf.y + 2 * h3, vf.w, h3])
press(Z, "opt", "cmd"); check("undo", [vf.x, vf.y, w3, vf.h])
press(Z, "opt", "shift", "cmd"); check("redo", [vf.x, vf.y + 2 * h3, vf.w, h3])

te.documents[0].close({ saving: "no" })
console.log(`\n${pass} passed, ${fail} failed`)
