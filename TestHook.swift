// TestHook.swift: commands sent by tests through a DistributedNotification (no window, no focus,
// no clicks). UI-only: nothing here can do more than the icon and Settings already can.
import AppKit
import SwiftUI

@MainActor enum TestHook {
    static func run(_ cmd: String, _ a: AppDelegate) {
        let p = cmd.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        func arg(_ i: Int) -> String { p.indices.contains(i) ? p[i] : "" }
        let engine = a.engine
        switch p[0] {
        case "panel": a.openPanel()
        case "close": a.closePanel(); a.iceBar.hide(); a.search.hide()
        case "tick": Task { await engine.tick() }
        case "sim":
            if arg(1) == "off" { engine.simulated = nil } else if let l = decodeLayout(arg(1)) { engine.simulated = l }
            Task { await engine.refresh() }
        case "set":   // set|auto|bundleID|1
            if arg(1) == "auto" { engine.setAuto(arg(2), arg(3) == "1") }
            if arg(1) == "never" { engine.setNever(arg(2), arg(3) == "1") }
            if arg(1) == "margin" { engine.margin = Double(arg(2)) ?? 40 }
            if arg(1) == "guard" { engine.guardOn = arg(2) == "1" }
        case "pref": setPref(arg(1), arg(2), a)
        case "section":   // section|show|hidden / section|show|always / section|hide / section|toggle
            switch arg(1) {
            case "show": a.sections.show(always: arg(2) == "always")
            case "hide": a.sections.hide()
            default: a.reveal(always: arg(2) == "always", toggle: true)
            }
        case "click": a.reveal(always: arg(1) == "option", toggle: true)        // same path as clicking the shield
        case "icebar": if arg(1) == "hide" { a.iceBar.hide() } else { a.showIceBar(always: arg(1) == "always") }
        case "search": Task { await engine.refresh(); a.search.show(entries: engine.entries, images: a.images); if !arg(1).isEmpty { a.search.model.query = arg(1) } }
        case "searchpick": a.search.pickSelected()
        case "press": if let e = engine.entries.first(where: { $0.id == arg(1) }) { a.press(e) }
        case "move": if let e = engine.entries.first(where: { $0.id == arg(1) }), let s = BarSection(rawValue: arg(2)) { a.move(e, to: s) }
        case "trigger":
            switch arg(1) {
            case "hover": a.triggers.testHover()
            case "click": a.triggers.testClickEmpty()
            case "scrollup": a.triggers.testScroll(true)
            case "scrolldown": a.triggers.testScroll(false)
            default: a.triggers.testAppSwitch()
            }
        case "hotkey": if let h = HotkeyAction(rawValue: arg(1)) { Hotkeys.shared.perform(h) }
        case "hotkeyset":   // hotkeyset|action|keyCode|carbonMods|display
            if let k = UInt32(arg(2)), let m = UInt32(arg(3)) { a.prefs.hotkeys[arg(1)] = HotkeyCombo(keyCode: k, carbonMods: m, display: arg(4)) }
            else { a.prefs.hotkeys[arg(1)] = nil }
        case "divlen":   // divlen|hidden|300  (experiments only)
            let it = arg(1) == "always" ? a.sections.alwaysItem : a.sections.hiddenItem
            it?.length = CGFloat(Double(arg(2)) ?? 18)
        case "arrange": a.arrangeSections()
        case "divmove":   // divmove|always|left : drags a divider 60 pt left with the real Command-drag code
            let it = arg(1) == "always" ? a.sections.alwaysItem : a.sections.hiddenItem
            a.sections.showForMoving()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let f = a.sections.frame(it) else { return }
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let from = CGPoint(x: f.midX, y: top - f.midY)
                Task.detached { _ = Mover.commandDrag(from: from, to: CGPoint(x: from.x - 60, y: from.y)) }
            }
        case "restoreshield":   // puts the shield back left of every other icon (where it was before the test)
            Task {
                await engine.refresh()
                let left = a.sections.leftLimit()
                guard let m = a.statusItem.button?.window?.frame,
                      let first = engine.entries.filter({ $0.x > left }).map(\.x).min(), m.minX > first else { return }
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let from = CGPoint(x: m.midX, y: top - m.midY)
                _ = await Task.detached { Mover.commandDrag(from: from, to: CGPoint(x: first - 6, y: from.y)) }.value
            }
        case "capture": Task { await a.peekCapture() }
        case "settings": a.openSettings(SettingsPane(rawValue: arg(1)))
        case "settingsoff": a.settings.showOffscreen(a.settingsView(), pane: SettingsPane(rawValue: arg(1)), dark: arg(2) == "dark")
        case "settingsclose": a.settings.close()
        case "state": writeState(arg(1), a)
        case "snap": snapshot(what: arg(1), dark: arg(2) == "dark", path: arg(3), extra: arg(4), a)
        default: break
        }
    }

    private static func setPref(_ k: String, _ v: String, _ a: AppDelegate) {
        let on = v == "1"
        let pr = a.prefs
        switch k {
        case "hiding": pr.hidingOn = on
        case "autohide": pr.autoHide = on
        case "always": pr.alwaysHiddenOn = on
        case "dividers": pr.showDividers = on
        case "icebar": pr.useIceBar = on
        case "notchonly": pr.iceBarNotchOnly = on
        case "hover": pr.showOnHover = on
        case "clickempty": pr.showOnClick = on
        case "scroll": pr.showOnScroll = on
        case "rehide": pr.autoRehide = on
        case "delay": pr.rehideDelay = Double(v) ?? 15
        case "appswitch": pr.rehideOnAppSwitch = on
        case "spacing": pr.spacingOffset = Int(v) ?? 0; SpacingApply.write(offset: pr.spacingOffset)
        case "look": if let c = try? JSONDecoder().decode(LookConfig.self, from: Data(v.utf8)) { pr.look = c }
        case "lookoff": pr.look.on = false
        case "hotkeys": pr.hotkeysOn = on
        case "search": pr.searchOn = on
        default: break
        }
    }

    static func decodeLayout(_ s: String) -> BarLayout? {
        struct W: Codable { var rightMin: CGFloat; var maxX: CGFloat; var items: [[String]] }
        guard let w = try? JSONDecoder().decode(W.self, from: Data(s.utf8)) else { return nil }
        let items = w.items.compactMap { a -> BarItem? in
            guard a.count == 4, let x = Double(a[2]), let wd = Double(a[3]) else { return nil }
            return BarItem(pid: 0, bundleID: a[0], name: a[1], x: x, width: wd)
        }
        return BarLayout(rightMin: w.rightMin, maxX: w.maxX, items: items)
    }

    private static func rect(_ r: CGRect?) -> [Double] { r.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? [] }

    static func writeState(_ path: String, _ a: AppDelegate) {
        let engine = a.engine, s = a.sections
        let l = engine.layout
        let d = s.dividers
        let sp = SpacingApply.read()
        let o: [String: Any] = [
            "verdict": "\(engine.verdict)", "trusted": engine.trusted, "guardOn": engine.guardOn,
            "free": l.map { Planner.free($0) } ?? -1, "macOverflow": l?.macOverflow ?? false, "ovFrame": "\(Scanner.overflowFrame)", "items": l?.items.count ?? 0,
            "quit": engine.quit.map(\.bundleID), "rules": engine.rules.map(\.bundleID),
            "auto": engine.rules.filter(\.autoQuit).map(\.bundleID), "never": engine.rules.filter(\.neverQuit).map(\.bundleID),
            "log": engine.log.prefix(30).map(\.text), "popoverShown": a.popover.isShown,
            "orderProblem": s.orderProblem, "collapsed": s.isCollapsed, "leftLimit": Double(s.leftLimit()),
            "hiddenShown": s.hiddenShown, "alwaysShown": s.alwaysShown, "tempShown": s.tempShown,
            "hiddenLength": Double(s.hiddenItem?.length ?? -1), "alwaysLength": Double(s.alwaysItem?.length ?? -1),
            "dividersInBar": [s.hiddenItem, s.alwaysItem].compactMap { $0 }.count,
            "dividerHidden": d.hidden.map(Double.init) ?? -1, "dividerAlways": d.always.map(Double.init) ?? -1,
            "mainFrame": rect(a.statusItem.button?.window?.frame),
            "hiddenFrame": rect(s.frame(s.hiddenItem)), "alwaysFrame": rect(s.frame(s.alwaysItem)),
            "entries": engine.entries.map { "\($0.id) x=\(Int($0.x)) w=\(Int($0.width)) \(SectionLogic.section($0, d).rawValue) \($0.label)" },
            "iceBarShown": a.iceBar.isShown, "iceBarActive": a.prefs.iceBarActive, "searchShown": a.search.isShown,
            "searchResults": a.search.model.results.prefix(5).map(\.id),
            "lookShown": a.look.isShown, "settingsShown": a.settings.isShown, "settingsWindow": a.settings.windowNumber,
            "images": a.images.images.keys.sorted(), "screenRecording": a.images.allowed,
            "spacing": sp.spacing ?? -1, "padding": sp.padding ?? -1,
            "hotkeyStatus": Hotkeys.shared.status.mapValues { Int($0) },
            "appMenusMaxX": Double(a.triggers.debugAppMenusMaxX),
            "frontApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Draws a screen into a PNG without showing any window.
    static func snapshot(what: String, dark: Bool, path: String, extra: String, _ a: AppDelegate) {
        let scheme: ColorScheme = dark ? .dark : .light
        if what.hasPrefix("intro") {
            let iv = IntroView(accent: guardAccent, actions: a.introActions(live: false), page: Int(what.dropFirst(5)) ?? 0)
            Snap.render(AnyView(iv), size: CGSize(width: 488, height: 560), dark: dark, path: path)
        } else if what.hasPrefix("settings-") {
            let pane = SettingsPane.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == String(what.dropFirst(9)) } ?? .general
            let nav = SettingsNav(); nav.pane = pane
            let v = SettingsView(nav: nav, engine: a.engine, prefs: a.prefs, sections: a.sections, images: a.images, actions: a.settingsActions)
            Snap.render(AnyView(v.background(Color(nsColor: .windowBackgroundColor))), size: CGSize(width: 760, height: Double(extra) ?? 560), dark: dark, path: path)
        } else if what == "icebar" {
            let d = a.sections.dividers
            let list = a.engine.entries.filter { SectionLogic.section($0, d) != .visible }
            a.iceBar.snapshot(entries: list.isEmpty ? Array(a.engine.entries.prefix(5)) : list, images: a.images, dark: dark, path: path)
        } else if what == "search" {
            a.search.snapshot(entries: a.engine.entries, query: extra, images: a.images, dark: dark, path: path)
        } else if what == "look" {
            var c = a.prefs.look
            if let j = try? JSONDecoder().decode(LookConfig.self, from: Data(extra.utf8)) { c = j }
            a.look.snapshot(config: c, dark: dark, path: path)
        } else {
            Snap.render(AnyView(a.panel(tab: what).environment(\.colorScheme, scheme)), size: CGSize(width: 380, height: 560), dark: dark, path: path)
        }
    }
}
