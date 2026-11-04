// Engine.swift: watches the menu bar, closes the lowest-priority allowed apps when it is full,
// remembers what it closed and brings them back when there is room. Never force-quits anything.
import AppKit
import Combine
import ServiceManagement

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
    var kind: String        // info, quit, restore, warn
}

@MainActor final class Engine: ObservableObject {
    @Published var rules: [Rule] = []
    @Published var quit: [QuitRecord] = []
    @Published var log: [LogEntry] = []
    @Published var layout: BarLayout?
    /// Every menu bar icon from the last scan, left to right (for the Ice Bar, search and Settings).
    @Published var entries: [BarEntry] = []
    @Published var verdict: Verdict = .ok
    @Published var trusted = Scanner.trusted()
    @Published var guardOn = true { didSet { save() } }
    @Published var autoRestore = true { didSet { save() } }
    @Published var margin: Double = 40 { didSet { save() } }
    @Published var busy = false
    @Published var openCount = 0

    /// Tests inject a made-up menu bar here instead of the real one.
    var simulated: BarLayout?
    /// The hidden sections. Icons hidden on purpose never count as "pushed behind the notch".
    weak var sections: SectionController?
    private var timer: Timer?
    private var debounce: DispatchWorkItem?
    private var warnedNoCandidate = false
    private let d = UserDefaults.standard
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    private let ownID = Bundle.main.bundleIdentifier ?? "com.solomon.MenuBarGuard"

    init() {
        load()
        if rules.isEmpty { rules = Planner.seed }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleTick() }
            }
        }
        Task { await tick() }
    }

    private func scheduleTick() {
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in await self?.tick() } }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }

    // MARK: Reading the bar

    func currentLayout() async -> BarLayout? {
        if let s = simulated { trusted = true; return s }
        trusted = Scanner.trusted()
        guard trusted else { return nil }
        let g = Scanner.geometry()
        let pid = selfPID
        let all = await Task.detached { Scanner.scanEntries(selfPID: pid) }.value
        entries = all
        guard let sec = sections else { return SectionLogic.layout(all, rightMin: g.rightMin, maxX: g.maxX) }
        let visible = SectionLogic.onScreen(all, dividers: sec.dividers, shown: sec.shownSections)
        return SectionLogic.layout(visible, rightMin: g.rightMin, maxX: g.maxX)
    }

    func refresh() async {
        sections?.refit()
        guard let l = await currentLayout() else { layout = nil; return }
        layout = l
        verdict = Planner.verdict(l, margin: margin)
        discover(l)
    }

    /// Third-party apps with menu bar icons join the priority list (at the bottom, not auto-quit).
    private func discover(_ l: BarLayout) {
        var changed = false
        for it in l.items where !it.bundleID.hasPrefix("com.apple.") && it.bundleID != ownID {
            let path = NSRunningApplication(processIdentifier: it.pid)?.bundleURL?.path
            if let i = rules.firstIndex(where: { $0.bundleID == it.bundleID }) {
                if rules[i].path != path, path != nil { rules[i].path = path; changed = true }
            } else {
                rules.append(Rule(bundleID: it.bundleID, name: it.name, path: path)); changed = true
            }
        }
        let present = Set(l.items.map(\.bundleID))
        let before = quit.count
        quit.removeAll { present.contains($0.bundleID) }      // the user (or something) reopened it
        if changed || quit.count != before { save() }
    }

    // MARK: Acting

    func tick() async {
        guard !busy else { return }
        await refresh()
        guard guardOn, trusted, layout != nil else { return }
        if verdict != .ok {
            // Items can still be sliding into place right after a launch: confirm before acting.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refresh()
            // Hide icons first: if hidden sections are open, close them and look again.
            if verdict != .ok, let sec = sections, sec.anyShown, !sec.tempShown {
                sec.hide()
                add("Menu bar was full, so Guard hid the hidden icons again first.", "info")
                try? await Task.sleep(nanoseconds: 900_000_000)
                await refresh()
            }
            // Only if the bar is still full after hiding: quit low-priority apps.
            if verdict != .ok { await shed() }
        } else {
            warnedNoCandidate = false
            if autoRestore { await restoreOne() }
        }
    }

    private func shed() async {
        busy = true; defer { busy = false }
        var skip = Set<String>(), count = 0
        while verdict != .ok, count < 5, let l = layout {
            guard let rule = Planner.nextToQuit(l, rules: rules, skip: skip) else {
                if !warnedNoCandidate {
                    add("Menu bar is \(verdict == .overflow ? "full" : "almost full"), but no app is set to Auto-quit.", "warn")
                    warnedNoCandidate = true
                }
                break
            }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID).first else {
                skip.insert(rule.bundleID); continue
            }
            let width = (l.items.first { $0.bundleID == rule.bundleID }?.width ?? 30)
            add("Menu bar \(verdict == .overflow ? "full" : "nearly full") (\(Int(Planner.free(l))) pt free). Asking \(rule.name) to quit.", "quit")
            let path = rule.path ?? app.bundleURL?.path     // read before it quits
            app.terminate()
            var waited = 0.0
            while !app.isTerminated, waited < 8 { try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25 }
            if app.isTerminated {
                quit.removeAll { $0.bundleID == rule.bundleID }
                quit.append(QuitRecord(bundleID: rule.bundleID, name: rule.name, path: path,
                                       width: width, date: Date()))
                add("\(rule.name) quit. Click Restart in the panel to bring it back.", "quit")
            } else {
                add("\(rule.name) did not quit within 8 seconds. Left running.", "warn")
                skip.insert(rule.bundleID)
            }
            save()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refresh()
            count += 1
        }
        if verdict == .ok { add("Menu bar has room again (\(Int(Planner.free(layout ?? BarLayout(rightMin: 0, maxX: 0, items: [])))) pt free).", "info") }
    }

    private func restoreOne() async {
        guard let l = layout, let rec = Planner.nextToRestore(l, rules: rules, quit: quit, margin: margin) else { return }
        busy = true; defer { busy = false }
        add("There is room again. Restarting \(rec.name).", "restore")
        await relaunch(rec)
    }

    func relaunch(_ rec: QuitRecord) async {
        guard let path = rec.path ?? appPath(bundleID: rec.bundleID) else { add("Cannot restart \(rec.name): its location is unknown. Start it by hand.", "warn"); quit.removeAll { $0.bundleID == rec.bundleID }; save(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false; cfg.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
            quit.removeAll { $0.bundleID == rec.bundleID }; save()
        } catch {
            add("Could not restart \(rec.name): \(error.localizedDescription)", "warn")
        }
    }

    func restartAll() { Task { for r in quit { await relaunch(r) }; await refresh() } }
    func restart(_ r: QuitRecord) { Task { await relaunch(r); await refresh() } }

    // MARK: Editing

    func move(_ from: IndexSet, _ to: Int) { rules = Planner.move(rules, from: from, to: to); save() }
    func setNever(_ id: String, _ v: Bool) { edit(id) { $0.neverQuit = v; if v { $0.autoQuit = false } } }
    func setAuto(_ id: String, _ v: Bool) { edit(id) { $0.autoQuit = v && !$0.neverQuit } }
    private func edit(_ id: String, _ f: (inout Rule) -> Void) {
        guard let i = rules.firstIndex(where: { $0.bundleID == id }) else { return }
        f(&rules[i]); save()
    }
    /// Where an app lives, so its real icon can be shown even when it is not running.
    func appPath(_ r: Rule) -> String? { r.path ?? appPath(bundleID: r.bundleID) }
    func appPath(bundleID: String) -> String? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path }
    func clearLog() { log = []; save() }

    func add(_ text: String, _ kind: String) {
        log.insert(LogEntry(date: Date(), text: text, kind: kind), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
        save()
    }

    // MARK: Login item

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {}
            objectWillChange.send()
        }
    }

    // MARK: Saving

    private func save() {
        let e = JSONEncoder()
        if let v = try? e.encode(rules) { d.set(v, forKey: "rules") }
        if let v = try? e.encode(quit) { d.set(v, forKey: "quit") }
        if let v = try? e.encode(log) { d.set(v, forKey: "log") }
        d.set(guardOn, forKey: "guardOn"); d.set(autoRestore, forKey: "autoRestore"); d.set(margin, forKey: "margin")
    }

    private func load() {
        let x = JSONDecoder()
        if let v = d.data(forKey: "rules"), let r = try? x.decode([Rule].self, from: v) { rules = r }
        if let v = d.data(forKey: "quit"), let r = try? x.decode([QuitRecord].self, from: v) { quit = r }
        if let v = d.data(forKey: "log"), let r = try? x.decode([LogEntry].self, from: v) { log = r }
        if d.object(forKey: "guardOn") != nil { guardOn = d.bool(forKey: "guardOn") }
        if d.object(forKey: "autoRestore") != nil { autoRestore = d.bool(forKey: "autoRestore") }
        if d.object(forKey: "margin") != nil { margin = d.double(forKey: "margin") }
    }
}
