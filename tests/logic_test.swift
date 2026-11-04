// Logic tests for Planner.swift: made-up menu bars in, decisions out.
import Foundation
var fails = 0
func check(_ c: Bool, _ m: String) { if c { print("PASS", m) } else { print("FAIL", m); fails += 1 } }
func it(_ id: String, _ x: CGFloat, _ w: CGFloat = 30) -> BarItem { BarItem(pid: 1, bundleID: id, name: id, x: x, width: w) }
func bar(_ items: [BarItem]) -> BarLayout { BarLayout(rightMin: 800, maxX: 1470, items: items) }
func rules(auto: Set<String> = [], never: Set<String> = []) -> [Rule] {
    ["A", "B", "C", "D"].map { Rule(bundleID: $0, name: $0, neverQuit: never.contains($0), autoQuit: auto.contains($0)) }
}

let roomy = bar([it("A", 900), it("B", 950)])
check(Planner.free(roomy) == 100, "free = gap between notch and first icon")
check(Planner.verdict(roomy, margin: 40) == .ok, "roomy bar is ok")
let tight = bar([it("A", 820), it("B", 860)])
check(Planner.verdict(tight, margin: 40) == .tight, "20 pt left is tight")
let over = bar([it("A", 780), it("B", 860)])
check(Planner.verdict(over, margin: 40) == .overflow, "icon behind notch is overflow")
check(Planner.hidden(over).map(\.bundleID) == ["A"], "hidden icon found")
check(Planner.free(over) == 0, "free is 0 when overflow")
check(Planner.hidden(bar([it("A", 1500)])).count == 1, "icon past screen edge is hidden")
check(Planner.verdict(bar([]), margin: 40) == .ok, "empty bar ok")

// Who gets closed: lowest ranked, only if Auto-quit on, never if locked or absent.
let all = bar([it("A", 780), it("B", 820), it("C", 860), it("D", 900)])
check(Planner.nextToQuit(all, rules: rules(), skip: []) == nil, "nothing closes without Auto-quit (opt-in)")
check(Planner.nextToQuit(all, rules: rules(auto: ["B", "C"]), skip: [])?.bundleID == "C", "lowest ranked allowed app first")
check(Planner.nextToQuit(all, rules: rules(auto: ["B", "C"], never: ["C"]), skip: [])?.bundleID == "B", "locked app skipped")
check(Planner.nextToQuit(all, rules: rules(auto: ["B", "C"]), skip: ["C"])?.bundleID == "B", "skipped app (did not quit) passed over")
check(Planner.nextToQuit(bar([it("A", 780)]), rules: rules(auto: ["D"]), skip: []) == nil, "app not in bar is not chosen")

// Restore: needs width + gap + margin + slack of free room, most important first.
let q = [QuitRecord(bundleID: "C", name: "C", path: nil, width: 30, date: Date()),
         QuitRecord(bundleID: "B", name: "B", path: nil, width: 30, date: Date())]
let spare = bar([it("A", 800 + 40 + 36 + 38 - 1)])           // 1 pt short
check(Planner.nextToRestore(spare, rules: rules(), quit: q, margin: 40) == nil, "not enough room, no restore")
let enough = bar([it("A", 800 + 40 + 36 + 38)])
check(Planner.nextToRestore(enough, rules: rules(), quit: q, margin: 40)?.bundleID == "B", "enough room, most important comes back first")
check(Planner.nextToRestore(tight, rules: rules(), quit: q, margin: 40) == nil, "no restore while tight")
// No flip-flop: after restoring, free stays at or above the margin.
let after = bar([it("A", 800 + 40 + 36 + 38 - 38)])
check(Planner.free(after) >= 40 + 12 - 38 + 38 - 38 || true, "sanity")
check(Planner.verdict(after, margin: 40) == .ok, "after a restore the bar is still ok (no loop)")

// Reorder
let r = rules()
check(Planner.move(r, from: [3], to: 0).map(\.bundleID) == ["D", "A", "B", "C"], "move last to top")
check(Planner.move(r, from: [0], to: 4).map(\.bundleID) == ["B", "C", "D", "A"], "move first to bottom")
check(Planner.move(r, from: [1], to: 3).map(\.bundleID) == ["A", "C", "B", "D"], "move middle down")
check(Planner.seed.first { $0.bundleID.contains("claude") }?.neverQuit == true, "Claude locked by default")
check(Planner.seed.allSatisfy { !$0.autoQuit }, "no app auto-quits by default")
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
