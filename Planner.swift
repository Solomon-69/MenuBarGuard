// Planner.swift: the pure decision logic. No AppKit, no side effects, so it can be tested by
// feeding it made-up menu bars. Everything is measured in points, left to right.
import CoreGraphics
import Foundation

struct BarItem: Equatable {
    var pid: Int32
    var bundleID: String
    var name: String
    var x: CGFloat
    var width: CGFloat
}

/// What the menu bar looks like right now. `rightMin` is where the free area for icons starts
/// (the right edge of the notch), `maxX` is the right edge of the screen.
struct BarLayout: Equatable {
    var rightMin: CGFloat
    var maxX: CGFloat
    var items: [BarItem]
}

enum Verdict: Equatable { case ok, tight, overflow }

struct Rule: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var path: String?
    var neverQuit: Bool = false
    var autoQuit: Bool = false
    var id: String { bundleID }
}

struct QuitRecord: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var path: String?
    var width: CGFloat
    var date: Date
    var id: String { bundleID }
}

enum Planner {
    /// Space one icon needs besides its own width (the gap macOS leaves between icons).
    static let gap: CGFloat = 8
    /// Extra room kept after bringing an app back, so it never flips straight back to "full".
    static let slack: CGFloat = 36

    /// Icons macOS pushed out of view: behind the notch, or off the screen.
    static func hidden(_ l: BarLayout) -> [BarItem] {
        l.items.filter { $0.x + $0.width / 2 < l.rightMin || $0.x >= l.maxX }
    }

    /// Empty room between the notch and the left-most visible icon. Zero when something is hidden.
    static func free(_ l: BarLayout) -> CGFloat {
        if !hidden(l).isEmpty { return 0 }
        guard let left = l.items.map(\.x).min() else { return max(0, l.maxX - l.rightMin) }
        return max(0, left - l.rightMin)
    }

    static func verdict(_ l: BarLayout, margin: CGFloat) -> Verdict {
        if !hidden(l).isEmpty { return .overflow }
        return free(l) < margin ? .tight : .ok
    }

    /// The lowest-ranked app that is allowed to be closed. `rules` run top (most important) to bottom.
    static func nextToQuit(_ l: BarLayout, rules: [Rule], skip: Set<String>) -> Rule? {
        let present = Set(l.items.map(\.bundleID))
        return rules.reversed().first {
            present.contains($0.bundleID) && $0.autoQuit && !$0.neverQuit && !skip.contains($0.bundleID)
        }
    }

    /// The most important closed app that fits back in with room to spare.
    static func nextToRestore(_ l: BarLayout, rules: [Rule], quit: [QuitRecord], margin: CGFloat) -> QuitRecord? {
        guard verdict(l, margin: margin) == .ok else { return nil }
        let room = free(l) - margin - slack
        let order = Dictionary(uniqueKeysWithValues: rules.enumerated().map { ($1.bundleID, $0) })
        return quit.sorted { (order[$0.bundleID] ?? 999) < (order[$1.bundleID] ?? 999) }
            .first { $0.width + gap <= room }
    }

    /// Drag-reorder: same behaviour as SwiftUI's `onMove`.
    static func move(_ rules: [Rule], from: IndexSet, to: Int) -> [Rule] {
        var r = rules
        let moving = from.sorted().map { r[$0] }
        let before = from.filter { $0 < to }.count
        for i in from.sorted(by: >) { r.remove(at: i) }
        r.insert(contentsOf: moving, at: to - before)
        return r
    }

    /// First-run order: the apps Solomon uses, most useful first. Everything else is added below.
    static let seed: [Rule] = [
        Rule(bundleID: "com.anthropic.claudefordesktop", name: "Claude", neverQuit: true),
        Rule(bundleID: "com.solomon.Tenax", name: "Memo"),
        Rule(bundleID: "com.aboudjem.Sleepless", name: "Awayke"),
        Rule(bundleID: "com.solomon.Stats", name: "Stats"),
        Rule(bundleID: "com.solomon.DarkSwitch", name: "Nox"),
        Rule(bundleID: "com.solomon.Nimbus", name: "Weather"),
        Rule(bundleID: "com.solomon.Ludus", name: "Ludus"),
    ]
}
