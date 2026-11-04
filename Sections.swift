// Sections.swift: the two divider icons that make the hidden and always-hidden sections.
// A divider hides everything to its left by growing very wide (10 000 pt), which pushes those
// icons off the screen. Shown, it shrinks back to a small chevron (or nothing).
import AppKit
import Combine

@MainActor final class SectionController: ObservableObject {
    static let collapsedLength: CGFloat = 10_000   // old trick, kept for reference; see set(_:collapsed:)
    static let dividerLength: CGFloat = 18

    @Published private(set) var hiddenShown = false
    @Published private(set) var alwaysShown = false
    /// Sections shown for a one-off job (pressing an icon from the Ice Bar or search). Rehide when done.
    private(set) var tempShown = false

    let prefs: Prefs
    private(set) var hiddenItem: NSStatusItem!
    private(set) var alwaysItem: NSStatusItem!
    private var rehideTimer: Timer?
    private var bag = Set<AnyCancellable>()
    var onChange: (() -> Void)?

    init(prefs: Prefs) { self.prefs = prefs }

    /// First launch only: where the shield and the dividers go (macOS remembers later moves itself).
    /// Positions count from the right edge of the screen. The shield goes just left of Apple's icons,
    /// the hidden divider just left of the shield (so other icons start hidden, like Ice), and the
    /// always-hidden divider left of every icon (empty until you move icons there).
    static func seedPositions(entries: [BarEntry]) {
        let d = UserDefaults.standard
        let key = { (n: String) in "NSStatusItem Preferred Position \(n)" }
        guard d.object(forKey: key("MBGMain")) == nil else { return }
        let maxX = NSScreen.screens.first { $0.auxiliaryTopRightArea != nil }?.frame.maxX ?? NSScreen.main?.frame.maxX ?? 1470
        let apple = entries.filter { $0.bundleID.hasPrefix("com.apple.") && $0.x > 0 }.map(\.x).min()
        let all = entries.filter { $0.x > 0 }.map(\.x).min()
        let main = apple.map { maxX - $0 + 4 } ?? 300
        d.set(Double(main), forKey: key("MBGMain"))
        d.set(Double(main + 40), forKey: key("MBGHidden"))
        d.set(Double(max(main + 80, (all.map { maxX - $0 } ?? 600) + 40)), forKey: key("MBGAlways"))
    }

    /// Call after the main icon exists. Dividers start small so macOS gives them a place,
    /// and only then grow to hide what is left of them.
    /// Nothing is added to the menu bar until hiding is switched on in Settings (off by default).
    func install() {
        prefs.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.apply() } }.store(in: &bag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.ready = true; self?.apply() }
    }
    private var ready = false

    private func make(_ name: String, _ label: String) -> NSStatusItem {
        let it = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        it.autosaveName = name
        it.isVisible = false; it.isVisible = true
        it.behavior = []          // cannot be dragged off the bar by accident
        if let b = it.button {
            b.imagePosition = .imageOnly
            b.target = self; b.action = #selector(dividerClicked)
            b.setAccessibilityLabel(label)
        }
        return it
    }

    /// A collapsed divider is an invisible 10 000 pt button over the empty menu bar space,
    /// so a click there lands here. Argument: true when it was collapsed (= empty space was clicked).
    var dividerClick: ((Bool) -> Void)?
    @objc private func dividerClicked() {
        let collapsed = isCollapsed
        if let f = dividerClick { f(collapsed) } else { hide() }
    }

    // MARK: Showing and hiding

    var anyShown: Bool { hiddenShown || alwaysShown }

    func show(always: Bool = false, temporary: Bool = false) {
        guard prefs.hidingOn else { return }
        hiddenShown = true
        if always && prefs.alwaysHiddenOn { alwaysShown = true }
        tempShown = temporary
        apply()
        scheduleRehide()
    }

    func hide() {
        rehideTimer?.invalidate(); rehideTimer = nil
        guard anyShown else { return }
        hiddenShown = false; alwaysShown = false; tempShown = false
        apply()
    }

    func toggle(always: Bool = false) {
        if always ? alwaysShown : hiddenShown { hide() } else { show(always: always) }
    }

    /// Restarts the auto-rehide countdown (for example after the pointer leaves the menu bar).
    func scheduleRehide() {
        rehideTimer?.invalidate(); rehideTimer = nil
        guard anyShown, prefs.autoRehide else { return }
        let t = Timer(timeInterval: max(2, prefs.rehideDelay), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.rehideIfIdle() }
        }
        RunLoop.main.add(t, forMode: .common)
        rehideTimer = t
    }

    /// Timed rehide waits while the pointer is still on the menu bar (you may be about to click an icon).
    private func rehideIfIdle() {
        if MenuBarGeometry.pointerInMenuBar() { scheduleRehide() } else { hide() }
    }

    /// Lays the dividers out for the current state.
    func apply() {
        guard ready else { return }
        let on = prefs.hidingOn
        if syncItems() {          // just added: let macOS place them, then measure
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.apply() }
            onChange?(); return
        }
        if !on { hiddenShown = false; alwaysShown = false; rehideTimer?.invalidate(); onChange?(); return }
        guard hiddenItem != nil else { return }
        checkOrder()
        // Never hide the shield itself: if it sits left of the divider, nothing is collapsed until it is fixed.
        let collapseHidden = on && !hiddenShown && !orderProblem
        let collapseAlways = on && prefs.alwaysHiddenOn && !alwaysShown && !orderProblem && !collapseHidden
        set(hiddenItem, collapsed: collapseHidden, symbol: "chevron.compact.left")
        if let a = alwaysItem { set(a, collapsed: collapseAlways, symbol: "chevron.left.2", parked: collapseHidden) }
        onChange?()
    }

    /// Adds or removes the divider icons to match the settings. Returns true if one was just added.
    private func syncItems() -> Bool {
        var added = false
        if prefs.hidingOn {
            if hiddenItem == nil { hiddenItem = make("MBGHidden", "Hidden section divider"); added = true }
        } else if let h = hiddenItem { NSStatusBar.system.removeStatusItem(h); hiddenItem = nil; rightEdge = [:] }
        if prefs.hidingOn && prefs.alwaysHiddenOn {
            if alwaysItem == nil { alwaysItem = make("MBGAlways", "Always-hidden section divider"); added = true }
        } else if let a = alwaysItem { NSStatusBar.system.removeStatusItem(a); alwaysItem = nil; alwaysShown = false }
        return added
    }

    /// The shield must be right of the hidden divider, or hiding would hide the shield too.
    @Published private(set) var orderProblem = false
    var mainFrame: () -> CGRect? = { nil }
    private var rightEdge: [ObjectIdentifier: CGFloat] = [:]

    private func checkOrder() {
        guard let m = mainFrame(), let h = frame(hiddenItem), hiddenItem.length <= Self.dividerLength + 0.5 else { return }
        orderProblem = m.minX < h.minX
    }

    /// Left end of the icon area: the notch's right edge, or the end of the app menus on other screens.
    var leftLimit: () -> CGFloat = {
        if let r = MenuBarGeometry.screen?.auxiliaryTopRightArea { return r.minX }
        return (MenuBarGeometry.screen?.frame.minX ?? 0) + 400
    }

    /// Collapsed, a divider grows just enough to reach the left end of the icon area, which pushes
    /// every icon left of it out of sight. (macOS 26+ drops an item that is wider than the space left,
    /// so the old 10 000 pt trick no longer works; the width is measured instead.)
    private func set(_ it: NSStatusItem, collapsed: Bool, symbol: String, parked: Bool = false) {
        let small = it.length <= Self.dividerLength + 0.5
        if small, let f = frame(it), f.width < 60 { rightEdge[ObjectIdentifier(it)] = f.maxX }
        if collapsed {
            let right = rightEdge[ObjectIdentifier(it)] ?? frame(it)?.maxX ?? 0
            let debug = UserDefaults.standard.bool(forKey: "debugNoCollapse")
            it.length = debug ? 24 : max(Self.dividerLength, right - leftLimit() - 2)
            it.button?.image = nil
        } else {
            // Parked: the always-hidden divider is already out of sight behind the collapsed hidden one.
            it.length = parked || prefs.showDividers ? Self.dividerLength : 0
            let img = parked || !prefs.showDividers ? nil : NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            img?.isTemplate = true
            it.button?.image = img
        }
        it.button?.alphaValue = 0.7
    }

    var isCollapsed: Bool { hiddenItem != nil && hiddenItem.length > Self.dividerLength + 0.5 }

    /// Icons to the right of the divider changed width (an app started or quit): keep the divider
    /// reaching exactly to the left end, so nothing peeks out and the divider is never dropped.
    func refit() {
        // Not collapsed although it should be (frames were not ready yet, or the order was just fixed): lay out again.
        if ready, prefs.hidingOn, !hiddenShown, !isCollapsed { apply() }
        for it in [hiddenItem as NSStatusItem?, alwaysItem as NSStatusItem?].compactMap({ $0 }) where it.length > Self.dividerLength + 0.5 {
            guard let f = frame(it) else { continue }
            let gap = f.minX - leftLimit()
            if abs(gap - 2) > 6 {
                it.length = max(Self.dividerLength, it.length + gap - 2)
                rightEdge[ObjectIdentifier(it)] = f.maxX
            }
        }
    }

    /// Shows both dividers with icons for a moment, for moving icons between sections.
    func showForMoving() {
        guard hiddenItem != nil else { return }
        hiddenShown = true; alwaysShown = prefs.alwaysHiddenOn; tempShown = true
        rehideTimer?.invalidate()
        hiddenItem.length = Self.dividerLength; alwaysItem?.length = Self.dividerLength
        for (it, s) in [(hiddenItem as NSStatusItem?, "chevron.compact.left"), (alwaysItem as NSStatusItem?, "chevron.left.2")].compactMap({ $0.0 == nil ? nil : ($0.0!, $0.1) }) {
            let img = NSImage(systemSymbolName: s, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            img?.isTemplate = true; it.button?.image = img
        }
        onChange?()
    }

    // MARK: Where things are

    func frame(_ it: NSStatusItem?) -> CGRect? {
        guard let it, it.isVisible, let w = it.button?.window else { return nil }
        // Screen frames are bottom-left based; icons (Accessibility) are top-left based. Only x is compared.
        return w.frame
    }

    var dividers: Dividers {
        Dividers(hidden: prefs.hidingOn ? frame(hiddenItem)?.minX : nil,
                 always: prefs.hidingOn && prefs.alwaysHiddenOn ? frame(alwaysItem)?.minX : nil)
    }

    var shownSections: Set<BarSection> {
        var s: Set<BarSection> = [.visible]
        if hiddenShown { s.insert(.hidden) }
        if alwaysShown { s.insert(.alwaysHidden) }
        return s
    }
}

/// Where the menu bar is and whether the pointer is on it.
enum MenuBarGeometry {
    @MainActor static var screen: NSScreen? { NSScreen.screens.first { $0.auxiliaryTopRightArea != nil } ?? NSScreen.main }

    @MainActor static func height(_ s: NSScreen) -> CGFloat {
        let h = s.frame.maxY - s.visibleFrame.maxY
        return h > 10 ? h : max(24, s.safeAreaInsets.top)
    }

    /// Pointer on the menu bar strip of any screen (bottom-left coordinates).
    @MainActor static func pointerInMenuBar(_ p: CGPoint = NSEvent.mouseLocation) -> Bool {
        NSScreen.screens.contains { s in
            p.x >= s.frame.minX && p.x <= s.frame.maxX && p.y >= s.frame.maxY - height(s) - 1 && p.y <= s.frame.maxY + 1
        }
    }
}
