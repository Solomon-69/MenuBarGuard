// Real-data check: reads the actual menu bar with the real Scanner and judges it with the real Planner.
import AppKit
let (rm, mx) = await MainActor.run { Scanner.geometry() }
let items = Scanner.scanItems(selfPID: 0).sorted { $0.x < $1.x }
let l = BarLayout(rightMin: rm, maxX: mx, items: items)
print("trusted:", Scanner.trusted(), "rightMin:", rm, "maxX:", mx)
for i in items { print(String(format: "%7.1f %5.1f  %@", i.x, i.width, i.bundleID)) }
print("free:", Planner.free(l), "verdict:", Planner.verdict(l, margin: 40), "hidden:", Planner.hidden(l).count)
