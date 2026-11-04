// App.swift: menu bar icon, popover, hidden sections, Ice Bar, search, Settings, welcome window and the test hook.
import AppKit
import Combine
import SwiftUI

@main enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let d = AppDelegate()
        app.delegate = d
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(d) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()
    let prefs = Prefs.shared
    lazy var sections = SectionController(prefs: prefs)
    lazy var triggers = Triggers(prefs: prefs, sections: sections)
    lazy var look = LookController(prefs: prefs)
    let images = ItemImages()
    let iceBar = IceBarController()
    let search = SearchController()
    let settings = SettingsWindowController()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var introWindow: NSWindow?
    var clickMonitor: Any?
    var keyMonitor: Any?
    var tempMonitor: Any?
    var cancellables = Set<AnyCancellable>()
    static let testName = Notification.Name("com.solomon.MenuBarGuard.test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let d = UserDefaults.standard
        statusItem = NSStatusBar.system.statusItem(withLength: 30)      // the one icon, placed like before 1.1
        if let b = statusItem.button {
            b.imagePosition = .imageOnly
            b.action = #selector(statusClicked)
            b.target = self
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.setAccessibilityLabel("Menu Bar Guard")
        }
        updateIcon()
        Publishers.CombineLatest3(engine.$verdict, engine.$trusted, engine.$guardOn)
            .sink { [weak self] _, _, _ in DispatchQueue.main.async { self?.updateIcon() } }.store(in: &cancellables)

        popover.behavior = .applicationDefined
        popover.animates = true
        PopoverStyle.apply(popover)
        let host = NSHostingController(rootView: panel())
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        setUpHiding()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testCommand(_:)),
                                                            name: Self.testName, object: nil)
        engine.start()
        if !d.bool(forKey: "introDone") { showIntro() }
        // After an update macOS can drop the Accessibility switch, and Guard then silently does nothing. Ask once at launch.
        if d.bool(forKey: "introDone"), !Scanner.trusted(), ProcessInfo.processInfo.environment["MBG_NO_ASK"] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if !Scanner.trusted() { Scanner.askAccessibility() } }
        }
    }

    private func setUpHiding() {
        sections.mainFrame = { [weak self] in self?.statusItem.button?.window?.frame }
        sections.install()
        engine.sections = sections
        sections.dividerClick = { [weak self] collapsed in
            guard let self else { return }
            if collapsed { if self.prefs.showOnClick { self.reveal(always: NSEvent.modifierFlags.contains(.option)) } } else { self.sections.hide() }
        }
        sections.$hiddenShown.sink { [weak self] shown in
            guard shown else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.captureNow() }
        }.store(in: &cancellables)
        triggers.showIceBar = { [weak self] always in self?.showIceBar(always: always) }
        triggers.hideIceBar = { [weak self] in self?.iceBar.hide() }
        triggers.isIceBarShown = { [weak self] in self?.iceBar.isShown ?? false }
        triggers.iconSpans = { [weak self] in self?.engine.entries.map { $0.x...($0.x + $0.width) } ?? [] }
        triggers.start()
        // Switching the Ice Bar or hiding off closes the bar at once.
        Publishers.CombineLatest(prefs.$useIceBar, prefs.$hidingOn).sink { [weak self] ice, hiding in
            if !ice || !hiding { DispatchQueue.main.async { self?.iceBar.hide() } }
        }.store(in: &cancellables)
        iceBar.onPick = { [weak self] e in self?.press(e) }
        search.onPick = { [weak self] e in self?.press(e) }
        search.model.sectionOf = { [weak self] e in self.map { SectionLogic.section(e, $0.sections.dividers) } ?? .visible }
        look.iconsMinX = { [weak self] in
            guard let self else { return nil }
            let d = self.sections.dividers
            return self.engine.entries.filter { SectionLogic.section($0, d) == .visible && $0.x > 0 }.map(\.x).min()
        }
        look.start()
        engine.$entries.sink { [weak self] _ in DispatchQueue.main.async { if self?.prefs.look.on == true { self?.look.update() } } }
            .store(in: &cancellables)
        Hotkeys.shared.perform = { [weak self] a in self?.hotkey(a) }
        // Hotkeys are registered only after "Use hotkeys" is switched on in Settings.
        Publishers.CombineLatest(prefs.$hotkeys, prefs.$hotkeysOn)
            .sink { h, on in DispatchQueue.main.async { Hotkeys.shared.register(on ? h : [:]) } }.store(in: &cancellables)
        if prefs.spacingOffset != 0 { SpacingApply.write(offset: prefs.spacingOffset) }
    }

    func panel(tab: String = "Apps") -> some View {
        PopoverView(engine: engine, showIntro: { [weak self] in self?.showIntro() },
                    quitApp: { NSApp.terminate(nil) }, openSettings: { [weak self] in self?.openSettings() }, tab: tab).fixedSize()
    }

    // MARK: Icon

    func updateIcon() {
        let bad = !engine.trusted || engine.verdict != .ok
        let name = !engine.guardOn ? "shield.slash" : bad ? "exclamationmark.shield.fill" : "shield.lefthalf.filled"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Menu Bar Guard")
        img?.isTemplate = true
        statusItem.button?.image = img?.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
    }

    // MARK: Clicks on the shield

    /// Left-click: show or hide the hidden icons. Option-click: the always-hidden ones too.
    /// Right-click or Control-click: the panel. With hiding off, every click opens the panel.
    @objc func statusClicked() {
        let e = NSApp.currentEvent
        let flags = e?.modifierFlags ?? []
        let panelClick = e?.type == .rightMouseUp || flags.contains(.control)
        if let b = statusItem.button { bounce(b) }
        if panelClick || !prefs.hidingOn { popover.isShown ? closePanel() : openPanel(); return }
        if popover.isShown { closePanel() }
        reveal(always: flags.contains(.option), toggle: true)
    }

    func reveal(always: Bool, toggle: Bool = false) {
        if prefs.iceBarActive {
            if iceBar.isShown, toggle { iceBar.hide() } else { showIceBar(always: always) }
        } else if toggle, sections.anyShown, !always || sections.alwaysShown {
            sections.hide()
        } else {
            sections.show(always: always)
        }
    }

    func showIceBar(always: Bool) {
        Task {
            await engine.refresh()
            let d = sections.dividers
            let list = engine.entries.filter { let s = SectionLogic.section($0, d); return s == .hidden || (always && s == .alwaysHidden) }
            if images.allowed, list.contains(where: { images.image($0) == nil }), Date().timeIntervalSince(images.lastCapture) > 300 {
                await peekCapture()
            }
            iceBar.show(entries: list, images: images, under: statusItem.button?.window?.frame)
        }
    }

    /// Shows the hidden icons for a split second to take their pictures (at most every 5 minutes).
    func peekCapture() async {
        guard !sections.anyShown else { await images.capture(engine.entries); return }
        sections.show(always: true, temporary: true)
        try? await Task.sleep(nanoseconds: 350_000_000)
        await engine.refresh()
        await images.capture(engine.entries)
        sections.hide()
    }

    private func captureNow() {
        guard sections.anyShown, images.allowed else { return }
        Task { await engine.refresh(); await images.capture(engine.entries) }
    }

    // MARK: Opening a hidden icon's menu

    /// Shows the icon's section, then presses the icon (its own menu opens). Hides again afterwards.
    func press(_ e: BarEntry) {
        let s = SectionLogic.section(e, sections.dividers)
        if s != .visible { sections.show(always: s == .alwaysHidden, temporary: true) }
        Task {
            if s != .visible { try? await Task.sleep(nanoseconds: 350_000_000) }
            let ok = await Task.detached { Scanner.press(pid: e.pid, index: e.index) }.value
            if !ok {
                await engine.refresh()
                if let f = engine.entries.first(where: { $0.id == e.id })?.frame { Mover.click(at: CGPoint(x: f.midX, y: f.midY)) }
            }
            engine.add("Opened \(e.title) from \(s == .visible ? "search" : "the hidden icons").", "info")
            if s != .visible { watchForMenuClose() }
        }
    }

    /// After a one-off show: hide again once you click somewhere off the menu bar (the menu closed), or after 30 s.
    private func watchForMenuClose() {
        if let m = tempMonitor { NSEvent.removeMonitor(m) }
        tempMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .keyDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.endTemp() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.endTemp() }
    }

    private func endTemp() {
        if let m = tempMonitor { NSEvent.removeMonitor(m); tempMonitor = nil }
        if sections.tempShown { sections.hide() }
    }

    // MARK: Moving icons between sections

    func move(_ e: BarEntry, to target: BarSection) {
        guard engine.trusted else { engine.add("Moving icons needs Accessibility access.", "warn"); return }
        guard prefs.hidingOn else { engine.add("Turn on hiding in Settings > General first.", "warn"); return }
        Task {
            sections.showForMoving()
            try? await Task.sleep(nanoseconds: 450_000_000)
            await engine.refresh()
            guard let fresh = engine.entries.first(where: { $0.id == e.id }),
                  let hf = sections.frame(sections.hiddenItem), let main = statusItem.button?.window?.frame else {
                sections.hide(); engine.add("Could not find \(e.title) to move it.", "warn"); return
            }
            let af = prefs.alwaysHiddenOn ? sections.frame(sections.alwaysItem) : nil
            let x = SectionLogic.dropX(target: target, hiddenFrame: hf, alwaysFrame: af, mainMinX: main.minX)
            let from = CGPoint(x: fresh.frame.midX, y: fresh.frame.midY)
            let to = CGPoint(x: x, y: from.y)
            _ = await Task.detached { Mover.commandDrag(from: from, to: to) }.value
            try? await Task.sleep(nanoseconds: 500_000_000)
            await engine.refresh()
            let now = engine.entries.first(where: { $0.bundleID == e.bundleID && abs($0.width - e.width) < 2 }) ?? engine.entries.first { $0.bundleID == e.bundleID }
            let landed = now.map { SectionLogic.section($0, sections.dividers) }
            sections.hide()
            if landed == target { engine.add("Moved \(e.title) to \(target.title).", "info") }
            else { engine.add("Could not move \(e.title) (macOS did not accept the drag). Command-drag it in the menu bar instead.", "warn") }
            await engine.refresh()
        }
    }

    /// Puts the shield just left of Apple's icons, the hidden divider just left of the shield and the
    /// always-hidden divider left of every icon, with three quick Command-drags (only when you ask).
    func arrangeSections() {
        guard engine.trusted else { engine.add("Arranging needs Accessibility access.", "warn"); return }
        Task {
            sections.showForMoving()
            try? await Task.sleep(nanoseconds: 450_000_000)
            await engine.refresh()
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            func mid(_ f: CGRect) -> CGPoint { CGPoint(x: f.midX, y: top - f.midY) }
            let left = sections.leftLimit()
            if let m = statusItem.button?.window?.frame,
               let apple = engine.entries.filter({ $0.bundleID.hasPrefix("com.apple.") && $0.x > left }).map(\.x).min(), m.maxX < apple - 30 || m.minX > apple {
                _ = await Task.detached { Mover.commandDrag(from: mid(m), to: CGPoint(x: apple - 6, y: mid(m).y)) }.value
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            if let h = sections.frame(sections.hiddenItem), let m = statusItem.button?.window?.frame, h.minX > m.minX || m.minX - h.maxX > 12 {
                _ = await Task.detached { Mover.commandDrag(from: mid(h), to: CGPoint(x: m.minX - 6, y: mid(h).y)) }.value
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            await engine.refresh()
            if prefs.alwaysHiddenOn, let a = sections.frame(sections.alwaysItem),
               let first = engine.entries.filter({ $0.x > left && !$0.bundleID.hasPrefix("com.apple.") }).map(\.x).min(), a.minX > first {
                _ = await Task.detached { Mover.commandDrag(from: mid(a), to: CGPoint(x: first - 6, y: mid(a).y)) }.value
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            sections.hide(); sections.apply()
            engine.add(sections.orderProblem ? "Could not put the dividers in place. Command-drag the shield to the right of ‹." : "Dividers are in place: icons left of ‹ are hidden.", sections.orderProblem ? "warn" : "info")
            await engine.refresh()
        }
    }

    // MARK: Hotkeys

    func hotkey(_ a: HotkeyAction) {
        switch a {
        case .toggleHidden: if prefs.hidingOn { reveal(always: false, toggle: true) }
        case .toggleAlways: if prefs.hidingOn { reveal(always: true, toggle: true) }
        case .search:
            guard prefs.searchOn else { return }
            Task { await engine.refresh(); search.toggle(entries: engine.entries, images: images) }
        case .toggleIceBar: prefs.useIceBar.toggle(); iceBar.hide()
        case .toggleDividers: prefs.showDividers.toggle()
        case .openPanel: popover.isShown ? closePanel() : openPanel()
        }
    }

    // MARK: Popover

    func openPanel() {
        guard let b = statusItem.button, !popover.isShown else { return }
        engine.openCount += 1
        Task { await engine.refresh() }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        if let w = popover.contentViewController?.view.window {
            if !w.styleMask.contains(.nonactivatingPanel) { w.styleMask.insert(.nonactivatingPanel) }   // never steals focus
            w.makeKey()
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.closePanel(); return nil }
            return e
        }
    }

    func closePanel() {
        popover.performClose(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    func bounce(_ b: NSStatusBarButton) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = b.layer else { return }
        let a = CASpringAnimation(keyPath: "transform.scale")
        a.fromValue = 1.12; a.toValue = 1; a.stiffness = 320; a.damping = 11; a.mass = 1
        a.duration = a.settlingDuration
        layer.add(a, forKey: "bounce")
    }

    // MARK: Settings

    var settingsActions: SettingsActions {
        SettingsActions(
            move: { [weak self] e, s in self?.move(e, to: s) },
            arrange: { [weak self] in self?.arrangeSections() },
            rescan: { [weak self] in Task { await self?.engine.refresh(); if self?.sections.anyShown == true { self?.captureNow() } } },
            showIntro: { [weak self] in self?.showIntro() },
            askAccessibility: { Scanner.askAccessibility() },
            askScreenRecording: { [weak self] in self?.images.request() },
            applySpacing: { [weak self] relaunch in
                guard let self else { return }
                SpacingApply.write(offset: self.prefs.spacingOffset)
                self.engine.add("Icon spacing set to \(self.prefs.spacingOffset == 0 ? "default" : String(self.prefs.spacingOffset)).", "info")
                if relaunch {
                    let locked = Set(self.engine.rules.filter(\.neverQuit).map(\.bundleID))
                    SpacingApply.relaunch(SpacingApply.relaunchable(self.engine.entries, locked: locked)) { [weak self] t in self?.engine.add(t, "info") }
                }
            })
    }

    func settingsView() -> AnyView {
        AnyView(SettingsView(nav: settings.nav, engine: engine, prefs: prefs, sections: sections, images: images, actions: settingsActions))
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        closePanel()
        images.recheck()
        settings.show(settingsView(), pane: pane)
    }

    // MARK: Welcome

    func introActions(live: Bool) -> IntroActions {
        IntroActions(
            permissionReady: { Scanner.trusted() },
            setUpPermission: { if live { Scanner.askAccessibility() } },
            finish: { [weak self] open in
                guard live else { return }
                UserDefaults.standard.set(true, forKey: "introDone")
                self?.introWindow?.close(); self?.introWindow = nil
                if open { self?.openPanel() }
            },
            screenReady: { CGPreflightScreenCaptureAccess() },
            setUpScreen: { [weak self] in if live { self?.images.request() } })
    }

    func showIntro() {
        if introWindow == nil {
            let host = NSHostingController(rootView: IntroView(accent: guardAccent, actions: introActions(live: true)))
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.center()
            introWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        introWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Test hook (UI-only; nothing here can do more than the icon already can)

    @objc func testCommand(_ n: Notification) {
        guard let cmd = n.object as? String else { return }
        TestHook.run(cmd, self)
    }
}
