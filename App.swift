// App.swift: menu bar icon, popover, welcome window and the test hook.
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
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var introWindow: NSWindow?
    var clickMonitor: Any?
    var keyMonitor: Any?
    var cancellables = Set<AnyCancellable>()
    static let testName = Notification.Name("com.solomon.MenuBarGuard.test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
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

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testCommand(_:)),
                                                            name: Self.testName, object: nil)
        engine.start()
        if !UserDefaults.standard.bool(forKey: "introDone") { showIntro() }
    }

    func panel(tab: String = "Apps") -> some View {
        PopoverView(engine: engine, showIntro: { [weak self] in self?.showIntro() },
                    quitApp: { NSApp.terminate(nil) }, tab: tab).fixedSize()
    }

    // MARK: Icon

    func updateIcon() {
        let bad = !engine.trusted || engine.verdict != .ok
        let name = !engine.guardOn ? "shield.slash" : bad ? "exclamationmark.shield.fill" : "shield.lefthalf.filled"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Menu Bar Guard")
        img?.isTemplate = true
        statusItem.button?.image = img?.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
    }

    // MARK: Popover

    @objc func statusClicked() { popover.isShown ? closePanel() : openPanel() }

    func openPanel() {
        guard let b = statusItem.button, !popover.isShown else { return }
        engine.openCount += 1
        Task { await engine.refresh() }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        if let w = popover.contentViewController?.view.window {
            w.styleMask.insert(.nonactivatingPanel)   // never steals focus from the app in front
            w.makeKey()
        }
        bounce(b)
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

    // MARK: Welcome

    func showIntro() {
        if introWindow == nil {
            let actions = IntroActions(
                permissionReady: { Scanner.trusted() },
                setUpPermission: { _ = Scanner.trusted(prompt: true) },
                finish: { [weak self] open in
                    UserDefaults.standard.set(true, forKey: "introDone")
                    self?.introWindow?.close(); self?.introWindow = nil
                    if open { self?.openPanel() }
                })
            let host = NSHostingController(rootView: IntroView(accent: guardAccent, actions: actions))
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
        let p = cmd.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch p[0] {
        case "panel": openPanel()
        case "close": closePanel()
        case "tick": Task { await engine.tick() }
        case "sim":
            if p[1] == "off" { engine.simulated = nil } else if let l = Self.decodeLayout(p[1]) { engine.simulated = l }
            Task { await engine.refresh() }
        case "set":   // set|autoquit|bundleID|1
            if p[1] == "auto" { engine.setAuto(p[2], p[3] == "1") }
            if p[1] == "never" { engine.setNever(p[2], p[3] == "1") }
            if p[1] == "margin" { engine.margin = Double(p[2]) ?? 40 }
            if p[1] == "guard" { engine.guardOn = p[2] == "1" }
        case "state": writeState(p[1])
        case "snap": snapshot(what: p[1], dark: p[2] == "dark", path: p[3])
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

    func writeState(_ path: String) {
        let l = engine.layout
        let o: [String: Any] = [
            "verdict": "\(engine.verdict)", "trusted": engine.trusted, "guardOn": engine.guardOn,
            "free": l.map { Planner.free($0) } ?? -1, "items": l?.items.count ?? 0,
            "quit": engine.quit.map(\.bundleID), "rules": engine.rules.map(\.bundleID),
            "auto": engine.rules.filter(\.autoQuit).map(\.bundleID), "never": engine.rules.filter(\.neverQuit).map(\.bundleID),
            "log": engine.log.map(\.text), "popoverShown": popover.isShown,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Draws a screen into a PNG without showing any window.
    func snapshot(what: String, dark: Bool, path: String) {
        let scheme: ColorScheme = dark ? .dark : .light
        let size: CGSize
        let view: AnyView
        if what.hasPrefix("intro") {
            let page = Int(what.dropFirst(5)) ?? 0
            let actions = IntroActions(permissionReady: { Scanner.trusted() }, setUpPermission: {}, finish: { _ in })
            let iv = IntroView(accent: guardAccent, actions: actions, page: page)
            view = AnyView(iv.environment(\.colorScheme, scheme)); size = CGSize(width: 488, height: 560)
        } else {
            view = AnyView(panel(tab: what).environment(\.colorScheme, scheme)); size = CGSize(width: 380, height: 560)
        }
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))     // let springs settle
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
