// Logic tests for SectionLogic.swift: sections, hide-first planning, search, drop spots, spacing.
// Run: cp tests/section_test.swift /private/tmp/mbg/main.swift && swiftc Planner.swift SectionLogic.swift /private/tmp/mbg/main.swift -o /private/tmp/mbg/st && /private/tmp/mbg/st
import Foundation
var fails = 0
func check(_ c: Bool, _ m: String) { if c { print("PASS", m) } else { print("FAIL", m); fails += 1 } }
func e(_ id: String, _ x: CGFloat, _ w: CGFloat = 30, _ label: String = "") -> BarEntry {
    BarEntry(pid: 1, bundleID: id, appName: id, index: 0, x: x, y: 4, width: w, height: 24, label: label)
}

// Sections: left of a divider = that divider's section.
let d = Dividers(hidden: 900, always: 700)
check(SectionLogic.section(e("A", 600), d) == .alwaysHidden, "left of always divider is always hidden")
check(SectionLogic.section(e("B", 800), d) == .hidden, "between dividers is hidden")
check(SectionLogic.section(e("C", 950), d) == .visible, "right of hidden divider is visible")
check(SectionLogic.section(e("B2", 870, 30), d) == .hidden, "touching the divider still counts as left of it")
check(SectionLogic.section(e("C", 950), Dividers(hidden: nil, always: nil)) == .visible, "hiding off: everything visible")
// Collapsed: divider 10 000 pt wide, its left edge far off screen, hidden icons further left.
let collapsed = Dividers(hidden: -8_900, always: -18_900)
check(SectionLogic.section(e("H", -8_940), collapsed) == .hidden, "collapsed hidden section still found")
check(SectionLogic.section(e("V", 1_100), collapsed) == .visible, "visible stays visible when collapsed")

// Hide first: hidden icons pushed off screen are not "overflow".
let all = [e("H", -8_940), e("V", 1_100), e("W", 1_140)]
let on = SectionLogic.onScreen(all, dividers: collapsed, shown: [.visible])
check(on.map(\.bundleID) == ["V", "W"], "icons hidden on purpose are left out")
let l = SectionLogic.layout(on, rightMin: 825, maxX: 1470)
check(Planner.verdict(l, margin: 40) == .ok, "bar with hidden section collapsed is ok (no quit)")
let lFull = SectionLogic.layout(all, rightMin: 825, maxX: 1470)
check(Planner.verdict(lFull, margin: 40) == .overflow, "same bar counted naively would overflow (why the filter matters)")
let shownAll = SectionLogic.onScreen(all, dividers: collapsed, shown: [.visible, .hidden])
check(shownAll.count == 3, "shown section counts again")
// Still full after hiding: auto-quit decides on visible icons only.
let crowded = [e("V1", 700), e("V2", 760), e("H", -8_940)]
let crowdedOn = SectionLogic.layout(SectionLogic.onScreen(crowded, dividers: Dividers(hidden: -8_900, always: nil), shown: [.visible]), rightMin: 825, maxX: 1470)
check(Planner.verdict(crowdedOn, margin: 40) == .overflow, "visible icons behind the notch still overflow")
let rules = [Rule(bundleID: "V1", name: "V1", autoQuit: true), Rule(bundleID: "H", name: "H", autoQuit: true)]
check(Planner.nextToQuit(crowdedOn, rules: rules, skip: [])?.bundleID == "V1", "hidden-section app is never quit for space")

// Search
let items = [e("com.solomon.Tenax", 900, 28, "Memo clipboard history"), e("com.aboudjem.Sleepless", 940, 36, "Awayke"),
             e("com.solomon.Stats", 980, 30, "Stats")]
var named = items; named[0].appName = "Memo"; named[1].appName = "Awayke"; named[2].appName = "Stats"
check(SectionLogic.search("memo", named).first?.appName == "Memo", "search by name")
check(SectionLogic.search("clip", named).first?.appName == "Memo", "search by icon description word")
check(SectionLogic.search("awk", named).first?.appName == "Awayke", "letters in order match")
check(SectionLogic.search("zzz", named).isEmpty, "no match gives nothing")
check(SectionLogic.search("", named).count == 3, "empty search lists everything")
check(SectionLogic.search("s", named).first?.appName == "Stats", "prefix beats word match")

// Drop spots for moving icons
let hf = CGRect(x: 900, y: 0, width: 18, height: 24), af = CGRect(x: 700, y: 0, width: 18, height: 24)
check(SectionLogic.dropX(target: .visible, hiddenFrame: hf, alwaysFrame: af, mainMinX: 1000) == 924, "visible: just right of the hidden divider")
check(SectionLogic.dropX(target: .hidden, hiddenFrame: hf, alwaysFrame: af, mainMinX: 1000) == 896, "hidden: just left of the hidden divider")
check(SectionLogic.dropX(target: .alwaysHidden, hiddenFrame: hf, alwaysFrame: af, mainMinX: 1000) == 696, "always: left of the always divider")
check(SectionLogic.dropX(target: .alwaysHidden, hiddenFrame: hf, alwaysFrame: nil, mainMinX: 1000) == 896, "no always divider: falls back to hidden")
check(SectionLogic.dropX(target: .visible, hiddenFrame: hf, alwaysFrame: nil, mainMinX: 920) == 916, "visible never lands on the shield")

// Spacing
check(Spacing.values(offset: 0) == nil, "offset 0 = system default")
check(Spacing.values(offset: -4)?.spacing == 12, "tighter by 4")
check(Spacing.values(offset: 99)?.spacing == 24, "clamped to +8")
check(Spacing.values(offset: -99)?.spacing == 8, "clamped to -8")
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
