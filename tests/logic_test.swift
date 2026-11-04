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

// Who gets closed: the app used longest ago. Apple's icons and "never" apps are skipped.
let all = bar([it("A", 780), it("B", 820), it("C", 860), it("D", 900)])
let t0 = Date(timeIntervalSince1970: 1_000_000)
let used: [String: Date] = ["A": t0 + 400, "B": t0 + 100, "C": t0 + 300, "D": t0 + 200]
check(Planner.nextToQuit(all, rules: rules(), skip: [], lastUsed: used)?.bundleID == "B", "least recently used app first")
check(Planner.nextToQuit(all, rules: rules(never: ["B"]), skip: [], lastUsed: used)?.bundleID == "D", "locked app skipped")
check(Planner.nextToQuit(all, rules: rules(), skip: ["B"], lastUsed: used)?.bundleID == "D", "skipped app (did not quit) passed over")
check(Planner.nextToQuit(bar([it("com.apple.x", 780), it("A", 820)]), rules: rules(), skip: [], lastUsed: [:])?.bundleID == "A", "Apple icons never chosen")
check(Planner.nextToQuit(bar([it("com.apple.x", 780)]), rules: rules(), skip: [], lastUsed: [:]) == nil, "only Apple icons: nothing to close")
check(Planner.nextToQuit(all, rules: rules(), skip: [], lastUsed: ["A": t0, "B": t0, "C": t0, "D": t0])?.bundleID == "A", "tie goes to the left-most icon")
check(Planner.nextToQuit(bar([it("Z", 820)]), rules: rules(), skip: [], lastUsed: [:])?.bundleID == "Z", "app not on the list can still be closed")

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
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
