// SectionLogic.swift: pure rules for the hidden sections, search and the icon gap setting.
// No AppKit, so it can be tested with made-up menu bars like Planner.swift.
import CoreGraphics
import Foundation

/// The three parts of the menu bar, left to right: always hidden | hidden | visible.
enum BarSection: String, Codable, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always hidden"
        }
    }
}

/// One menu bar icon (an app can own several).
struct BarEntry: Equatable, Identifiable {
    var pid: Int32
    var bundleID: String
    var appName: String
    var index: Int          // position among this app's own icons
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var label: String       // the icon's own accessibility description, if it has one
    var id: String { "\(bundleID)#\(index)" }
    var title: String { label.isEmpty || label == appName ? appName : "\(appName): \(label)" }
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Left edges (screen x) of the two divider icons Menu Bar Guard puts in the bar.
struct Dividers: Equatable {
    var hidden: CGFloat?
    var always: CGFloat?
}

enum SectionLogic {
    /// Which section an icon is in: anything left of a divider belongs to that divider's section.
    static func section(x: CGFloat, width: CGFloat, dividers: Dividers) -> BarSection {
        let right = x + width
        if let a = dividers.always, right <= a + 1 { return .alwaysHidden }
        if let h = dividers.hidden, right <= h + 1 { return .hidden }
        return .visible
    }

    static func section(_ e: BarEntry, _ d: Dividers) -> BarSection { section(x: e.x, width: e.width, dividers: d) }

    /// The icons that should be on screen right now. Icons Menu Bar Guard hid on purpose are left out,
    /// so they never count as "pushed behind the notch".
    static func onScreen(_ entries: [BarEntry], dividers: Dividers, shown: Set<BarSection>) -> [BarEntry] {
        entries.filter { shown.contains(section($0, dividers)) || section($0, dividers) == .visible }
    }

    /// Turns icons into the per-app layout the auto-quit planner works with.
    static func layout(_ entries: [BarEntry], rightMin: CGFloat, maxX: CGFloat) -> BarLayout {
        BarLayout(rightMin: rightMin, maxX: maxX, items: entries.map {
            BarItem(pid: $0.pid, bundleID: $0.bundleID, name: $0.appName, x: $0.x, width: $0.width)
        })
    }

    /// Search score: nil = no match. Higher is better. Matches words in any order, prefix first.
    static func score(_ query: String, _ text: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return 0 }
        let t = text.lowercased()
        if t.hasPrefix(q) { return 300 - t.count }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 200 - t.count }
        if t.contains(q) { return 100 - t.count }
        // Letters in order (e.g. "awk" finds "Awayke").
        var it = t.makeIterator()
        for ch in q { var found = false; while let c = it.next() { if c == ch { found = true; break } }; if !found { return nil } }
        return 10
    }

    static func search(_ query: String, _ entries: [BarEntry]) -> [BarEntry] {
        entries.compactMap { e in score(query, e.title + " " + e.bundleID).map { (e, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.x < $1.0.x }
            .map(\.0)
    }

    /// Where to drop an icon so it lands in `target`. Dividers are measured while every section is shown.
    /// `hiddenFrame` / `alwaysFrame` are the divider icons' frames, `mainMinX` is Menu Bar Guard's own icon.
    static func dropX(target: BarSection, hiddenFrame: CGRect, alwaysFrame: CGRect?, mainMinX: CGFloat) -> CGFloat {
        switch target {
        case .visible: return min(hiddenFrame.maxX + 6, mainMinX - 4)
        case .hidden: return alwaysFrame.map { max($0.maxX + 6, hiddenFrame.minX - 4) } ?? hiddenFrame.minX - 4
        case .alwaysHidden: return (alwaysFrame ?? hiddenFrame).minX - 4
        }
    }
}

/// The icon gap setting (macOS `NSStatusItemSpacing` / `NSStatusItemSelectionPadding`).
enum Spacing {
    static let base = 16, range = -8...8
    /// nil means "use the system default" (the keys are removed).
    static func values(offset: Int) -> (spacing: Int, padding: Int)? {
        let o = min(range.upperBound, max(range.lowerBound, offset))
        if o == 0 { return nil }
        return (base + o, max(2, base + o))
    }
}
