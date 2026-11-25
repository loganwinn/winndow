// Checks a rebound Next Third (⌘3) on a TextEdit window. Run after setting Next Third to ⌘3 in Edit Shortcuts.
ObjC.import("AppKit")
const se = Application("System Events"), te = Application("TextEdit")
te.activate(); te.documents.push(te.Document()); delay(1)
const scr = $.NSScreen.screens.js[0], v = scr.visibleFrame
const vf = { x: v.origin.x, y: scr.frame.size.height - v.origin.y - v.size.height, w: v.size.width, h: v.size.height }
const w3 = Math.floor(vf.w / 3)
const frame = () => { const b = te.windows[0].bounds(); return [b.x, b.y, b.width, b.height] }
const reset = () => { te.windows[0].bounds = { x: 200, y: 200, width: 800, height: 500 }; delay(0.3) }
let fail = 0
const check = (name, want) => { const g = frame(), ok = g.every((x, i) => Math.abs(x - want[i]) <= 2); if (!ok) fail++; console.log(`${ok ? "PASS" : "FAIL"} ${name}: got ${g} want ${want}`) }

reset()
te.activate(); delay(0.2); se.keyCode(20, { using: ["command down"] }); delay(0.6); check("⌘3 -> first third", [vf.x, vf.y, w3, vf.h])
te.activate(); delay(0.2); se.keyCode(20, { using: ["command down"] }); delay(0.6); check("⌘3 again -> second third", [vf.x + w3, vf.y, w3, vf.h])
reset()
te.activate(); delay(0.2); se.keyCode(124, { using: ["control down", "option down"] }); delay(0.6); check("old ⌃⌥→ does nothing now", [200, 200, 800, 500])
te.documents[0].close({ saving: "no" })
console.log(fail ? `${fail} failed` : "rebind: all passed")
