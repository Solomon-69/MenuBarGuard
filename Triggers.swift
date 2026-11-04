// Triggers.swift: other ways to show hidden icons (hover, click on empty menu bar space, scroll or
// swipe on the menu bar) and the automatic rehide when you switch apps or move away.
import AppKit
import Combine

@MainActor final class Triggers {
    let prefs: Prefs
    let sections: SectionController
    /// Called instead of showing inline when the Ice Bar is in use.
    var showIceBar: (_ always: Bool) -> Void = { _ in }
    var hideIceBar: () -> Void = {}
    var isIceBarShown: () -> Bool = { false }
    /// Frames (screen x) of every icon from the last scan, to tell empty space from icons.
    var iconSpans: () -> [ClosedRange<CGFloat>] = { [] }

    private var monitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var shownByHover = false
    private var appMenusMaxX: CGFloat = 0
    private var lastScroll = Date.distantPast

    init(prefs: Prefs, sections: SectionController) { self.prefs = prefs; self.sections = sections }

    func start() {
        let m1 = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }
        let m2 = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            let p = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.clicked(at: p, event: e) }
        }
        let m3 = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] e in
            let dy = e.scrollingDeltaY, dx = e.scrollingDeltaX
            MainActor.assumeIsolated { self?.scrolled(dx: dx, dy: dy) }
        }
        monitors = [m1, m2, m3].compactMap { $0 }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appSwitched() }
        }
        refreshAppMenus()
    }

    private func refreshAppMenus() {
        Task.detached { let x = Scanner.appMenusMaxX(); await MainActor.run { self.appMenusMaxX = x } }
    }

    /// Empty menu bar space: on the menu bar, right of the app's menus, not on an icon.
    func isEmptySpace(_ p: CGPoint) -> Bool {
        guard MenuBarGeometry.pointerInMenuBar(p) else { return false }
        if p.x <= appMenusMaxX + 4 { return false }
        if let s = MenuBarGeometry.screen, let notch = notchSpan(s), notch.contains(p.x) { return false }
        return !iconSpans().contains { $0.contains(p.x) }
    }

    private func notchSpan(_ s: NSScreen) -> ClosedRange<CGFloat>? {
        guard let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return nil }
        return l.maxX...r.minX
    }

    private func reveal(always: Bool = false) {
        if prefs.iceBarActive { if !isIceBarShown() { showIceBar(always) } } else { sections.show(always: always) }
    }

    private func conceal() {
        if prefs.iceBarActive { hideIceBar() } else { sections.hide() }
    }

    private var revealed: Bool { prefs.iceBarActive ? isIceBarShown() : sections.anyShown }

    // MARK: Hover

    private func moved() {
        guard prefs.hidingOn else { return }
        let p = NSEvent.mouseLocation
        let onBar = MenuBarGeometry.pointerInMenuBar(p)
        if prefs.showOnHover, onBar, !revealed, isEmptySpace(p) {
            if hoverWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self, self.isEmptySpace(NSEvent.mouseLocation) else { self?.hoverWork = nil; return }
                    self.shownByHover = true; self.hoverWork = nil; self.reveal()
                }
                hoverWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
            }
        } else if !onBar {
            hoverWork?.cancel(); hoverWork = nil
        }
        // Shown by hover: hide again shortly after the pointer leaves the menu bar (Ice Bar has its own rule).
        if shownByHover, !onBar, !prefs.iceBarActive, sections.anyShown {
            shownByHover = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !MenuBarGeometry.pointerInMenuBar() else { return }
                self.sections.hide()
            }
        } else if !onBar, sections.anyShown {
            sections.scheduleRehide()
        }
    }

    // MARK: Click on empty space

    private func clicked(at p: CGPoint, event: NSEvent) {
        guard prefs.hidingOn, prefs.showOnClick, isEmptySpace(p) else { return }
        if revealed { conceal() } else { reveal(always: event.modifierFlags.contains(.option)) }
    }

    // MARK: Scroll or swipe

    private func scrolled(dx: CGFloat, dy: CGFloat) {
        guard prefs.hidingOn, prefs.showOnScroll, MenuBarGeometry.pointerInMenuBar(),
              Date().timeIntervalSince(lastScroll) > 0.4 else { return }
        let v = abs(dy) >= abs(dx) ? dy : dx
        guard abs(v) > 2 else { return }
        lastScroll = Date()
        if v > 0 { if !revealed { reveal() } } else { conceal() }
    }

    // MARK: Focus moves

    private func appSwitched() {
        refreshAppMenus()
        guard prefs.autoRehide, prefs.rehideOnAppSwitch, sections.anyShown, !sections.tempShown else { return }
        // A click on a hidden icon can switch apps too; give its menu time to open first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !MenuBarGeometry.pointerInMenuBar() else { return }
            self.sections.hide()
        }
    }

    // Test hooks: run the same paths as real events.
    func testHover() { shownByHover = true; reveal() }
    func testClickEmpty() { if revealed { conceal() } else { reveal() } }
    func testScroll(_ up: Bool) { lastScroll = .distantPast; if up { if !revealed { reveal() } } else { conceal() } }
    func testAppSwitch() { guard prefs.autoRehide, prefs.rehideOnAppSwitch, sections.anyShown else { return }; sections.hide() }
    var debugAppMenusMaxX: CGFloat { appMenusMaxX }
}
