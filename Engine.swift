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

struct HiddenRecord: Codable, Identifiable, Equatable {
    var id: String          // BarEntry id (bundle ID and icon number)
    var bundleID: String
    var name: String
    var width: CGFloat
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
    /// Where Roomy's own icon sits in the bar (set by the app). It takes menu bar space too, so it counts.
    var ownFrame: () -> CGRect? = { nil }
    /// Set by the app: moves one icon to a section with a quick Command-drag. True when it landed there.
    var moveIcon: ((BarEntry, BarSection) async -> Bool)?
    /// Set by the app: drags the hidden divider to the far left of the bar (left of the shield too). True when it got there.
    var placeDivider: (() async -> Bool)?
    /// Icons Roomy hid itself (bundle ID + width), so it can bring them back when there is room.
    @Published var hiddenByGuard: [HiddenRecord] = []
    private var lastHideAt = Date.distantPast
    /// After a failed hide, stop trying for a while so the pointer is not dragged around every 2 seconds.
    private var noHideUntil = Date.distantPast
    /// When each app was last in front (or opened). The app used longest ago is closed or hidden first.
    private var lastUsed: [String: Date] = [:]
    private func usedAt(_ bundleID: String, _ pid: Int32) -> Date {
        lastUsed[bundleID] ?? NSRunningApplication(processIdentifier: pid)?.launchDate ?? .distantPast
    }
    /// The hidden sections. Icons hidden on purpose never count as "pushed behind the notch".
    weak var sections: SectionController?
    private var timer: Timer?
    private var debounce: DispatchWorkItem?
    private var warnedNoCandidate = false
    /// When the last app was closed. Nothing comes back for a while after that, so the bar never flips full, room, full.
    private var lastQuitAt = Date.distantPast
    /// When an app was last brought back. If the bar fills up right after, stop bringing apps back for 30 minutes (no close, reopen, close loop).
    private var lastRestoreAt = Date.distantPast
    private var noRestoreUntil = Date.distantPast
    /// Apps left inside macOS's « arrow after Roomy made room. Restarted once so they come back into the bar.
    private var stuck: [String] = []
    /// Apps closed while macOS's « arrow stayed up. At most 2 per sighting, so a stuck Apple icon never empties the bar.
    private var overflowQuits = 0
    private var arrowFixes: [Date] = []
    private var noFixUntil = Date.distantPast
    private let d = UserDefaults.standard
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    private let ownID = Bundle.main.bundleIdentifier ?? "com.solomon.MenuBarGuard"

    init() {
        load()
        if rules.isEmpty { rules = Planner.seed }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                let launched = note.name == NSWorkspace.didLaunchApplicationNotification
                Task { @MainActor in
                    if launched, let id { self?.justLaunched[id] = Date(); self?.lastUsed[id] = Date(); self?.saveUsed() }
                    self?.scheduleTick()
                }
            }
        }
        // Clicking an app's menu bar icon counts as using it (menu bar apps are rarely "in front").
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            let p = NSEvent.mouseLocation
            Task { @MainActor in self?.noteBarClick(p) }
        }
        if let f = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { lastUsed[f] = Date() }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
            Task { @MainActor in self?.lastUsed[id] = Date(); self?.saveUsed() }
        }
        Task { await tick() }
    }
    /// Apps opened in the last minute. If macOS drops a new one behind the « arrows, Roomy brings it out and closes an old app instead.
    private var justLaunched: [String: Date] = [:]
    private var clickMonitor: Any?

    private func noteBarClick(_ p: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) ?? NSScreen.main else { return }
        let fromTop = screen.frame.maxY - p.y
        guard fromTop >= 0, fromTop <= 40 else { return }
        let x = p.x - screen.frame.minX
        if let e = entries.first(where: { x >= $0.x - 2 && x <= $0.x + $0.width + 2 }), !e.bundleID.hasPrefix("com.apple.") {
            lastUsed[e.bundleID] = Date(); saveUsed()
        }
    }

    /// A just-opened app whose icon sits in the hidden part (behind the « arrows) that Roomy did not hide on purpose.
    private func newlyBuried() -> [BarEntry] {
        guard let sec = sections else { return [] }
        justLaunched = justLaunched.filter { Date().timeIntervalSince($0.value) < 90 }
        let mine = Set(hiddenByGuard.map(\.id))
        return entries.filter {
            justLaunched[$0.bundleID] != nil && !mine.contains($0.id) && $0.bundleID != ownID
                && SectionLogic.section($0, sec.dividers) == .hidden
        }
    }

    /// Bring a newly opened app out from behind the arrows. Afterwards the normal check closes the app used longest ago.
    private func unbury() async {
        guard let move = moveIcon else { return }
        let buried = newlyBuried()
        guard !buried.isEmpty else { return }
        busy = true
        for e in buried {
            add("\(e.title) opened behind the arrows. Moving it into the bar.", "info")
            if await move(e, .visible) { justLaunched[e.bundleID] = nil }
            else { add("Could not move \(e.title) out from behind the arrows.", "warn"); justLaunched[e.bundleID] = nil }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        busy = false
        await refresh()
    }

    private func saveUsed() { d.set(lastUsed.mapValues { $0.timeIntervalSince1970 }, forKey: "lastUsed") }

    private func scheduleTick() {
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in await self?.tick() } }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
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
        var lay: BarLayout
        if let sec = sections {
            let visible = SectionLogic.onScreen(all, dividers: sec.dividers, shown: sec.shownSections)
            lay = SectionLogic.layout(visible, rightMin: g.rightMin, maxX: g.maxX)
        } else {
            lay = SectionLogic.layout(all, rightMin: g.rightMin, maxX: g.maxX)
        }
        // macOS's « arrow means full, but it lingers a few seconds after an app closes, and only counts when the bar is really tight.
        var plain = lay; plain.macOverflow = false
        if !Scanner.sawOverflow { overflowQuits = 0 }   // arrow gone: episode over
        lay.macOverflow = false && Scanner.sawOverflow && overflowQuits < 2 && Date().timeIntervalSince(lastQuitAt) > 15
        _ = plain
        if let f = ownFrame(), f.width > 1 {
            lay.items.append(BarItem(pid: selfPID, bundleID: ownID, name: "Roomy", x: f.minX, width: f.width))
        }
        return lay
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
        if !newlyBuried().isEmpty { await unbury() }
        if Scanner.sawOverflow, Date().timeIntervalSince(lastQuitAt) > 15, Date() > noFixUntil { await fixArrow() }
        if verdict != .ok {
            // Items can still be sliding into place right after a launch: confirm before acting.
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
            // Hide icons first: if hidden sections are open, close them and look again.
            if verdict != .ok, let sec = sections, sec.anyShown, !sec.tempShown {
                sec.hide()
                add("Menu bar was full, so Roomy hid the hidden icons again first.", "info")
                try? await Task.sleep(nanoseconds: 900_000_000)
                await refresh()
            }
            // Close the app used longest ago (Solomon, 4 Nov 2026: never bury apps behind the arrows).
            if verdict != .ok { await shed() }
            // Only if nothing can be closed: hide icons, when the user turned that on.
            if verdict != .ok, Prefs.shared.autoHide, Date() > noHideUntil { await hideFirst() }
        } else {
            warnedNoCandidate = false
            if autoRestore, Date().timeIntervalSince(lastQuitAt) > 120, Date().timeIntervalSince(lastHideAt) > 120 {
                await restoreOne()
                if !busy { await unhideOne() }
            }
        }
    }

    // MARK: Hiding first

    /// Which visible icon to hide next: the lowest-ranked app on the priority list that is not marked "never".
    private func nextToHide(skip: Set<String>) -> BarEntry? {
        guard let sec = sections, let l = layout else { return nil }
        let lowest = l.rightMin
        let never = Set(rules.filter(\.neverQuit).map(\.bundleID))
        return entries.filter {
            !$0.bundleID.hasPrefix("com.apple.") && $0.bundleID != ownID && $0.pid != selfPID && !never.contains($0.bundleID)
                && !skip.contains($0.id) && $0.x + $0.width / 2 >= lowest && SectionLogic.section($0, sec.dividers) == .visible
        }.min { (usedAt($0.bundleID, $0.pid), $0.x) < (usedAt($1.bundleID, $1.pid), $1.x) }
    }

    private func hideFirst() async {
        guard let move = moveIcon, let sec = sections else { return }
        busy = true; defer { busy = false }
        let prefs = Prefs.shared
        guard prefs.hidingOn else { return }   // never switch hiding on by itself: that buried apps behind the arrows
        // The shield must sit right of the divider. If it does not (or the divider is not placed yet), put the divider far left.
        if sec.orderProblem || sec.dividers.hidden == nil || (sec.dividers.hidden ?? 0) > (entries.filter { $0.x > (layout?.rightMin ?? 0) }.map(\.x).max() ?? 0) {
            if let place = placeDivider, !(await place()) { add("Could not put the hiding divider in place.", "warn"); noHideUntil = Date().addingTimeInterval(300); return }
            await refresh()
        }
        var skip = Set<String>(), count = 0
        while verdict != .ok, count < 6, let e = nextToHide(skip: skip) {
            skip.insert(e.id)
            add("Menu bar \(verdict == .overflow ? "full" : "nearly full") (\(Int(Planner.free(layout ?? BarLayout(rightMin: 0, maxX: 0, items: [])))) pt free). Hiding \(e.title).", "info")
            if await move(e, .hidden) {
                hiddenByGuard.removeAll { $0.id == e.id }
                hiddenByGuard.append(HiddenRecord(id: e.id, bundleID: e.bundleID, name: e.title, width: e.width))
                lastHideAt = Date(); save()
            } else {
                add("Could not hide \(e.title).", "warn")
                noHideUntil = Date().addingTimeInterval(300); break
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
            count += 1
        }
        _ = sec
        if verdict == .ok, count > 0 { add("Hiding made room (\(Int(Planner.free(layout ?? BarLayout(rightMin: 0, maxX: 0, items: [])))) pt free). Click the shield to see hidden icons.", "info") }
    }

    /// Plenty of room again: put the most important icon Roomy hid back in the bar.
    private func unhideOne() async {
        guard let move = moveIcon, let sec = sections, let l = layout, verdict == .ok, !hiddenByGuard.isEmpty else { return }
        let order = Dictionary(uniqueKeysWithValues: rules.enumerated().map { ($1.bundleID, $0) })
        let room = Planner.free(l) - margin - Planner.slack
        guard let rec = hiddenByGuard.sorted(by: { (order[$0.bundleID] ?? 999) < (order[$1.bundleID] ?? 999) })
            .first(where: { $0.width + Planner.gap <= room }),
              let e = entries.first(where: { $0.id == rec.id }) else {
            hiddenByGuard.removeAll { r in !entries.contains { $0.id == r.id } }   // gone (app quit): forget it
            return
        }
        guard SectionLogic.section(e, sec.dividers) != .visible else { hiddenByGuard.removeAll { $0.id == rec.id }; save(); return }
        busy = true; defer { busy = false }
        add("There is room again. Showing \(rec.name).", "restore")
        if await move(e, .visible) { hiddenByGuard.removeAll { $0.id == rec.id }; save() }
        lastHideAt = Date()
        await refresh()
    }

    private func shed() async {
        busy = true; defer { busy = false }
        if Date().timeIntervalSince(lastRestoreAt) < 30 { noRestoreUntil = Date().addingTimeInterval(1800) }
        var skip = Set<String>([ownID]).union(justLaunched.keys), count = 0
        // Only apps marked Auto-quit may be closed (4 Nov 2026: it closed Awayke, which was never allowed).
        skip.formUnion(rules.filter { !$0.autoQuit }.map(\.bundleID))
        while verdict != .ok, count < 5, let l = layout {
            var used = lastUsed
            var cand = l
            // Apps whose icon macOS already pushed into its « arrow are not on screen, but count too.
            if l.macOverflow {
                let shown = Set(l.items.map(\.bundleID))
                for r in rules where !shown.contains(r.bundleID) && !r.bundleID.hasPrefix("com.apple.") && r.bundleID != ownID {
                    if let a = NSRunningApplication.runningApplications(withBundleIdentifier: r.bundleID).first {
                        cand.items.append(BarItem(pid: a.processIdentifier, bundleID: r.bundleID, name: r.name, x: -1000, width: 30))
                    }
                }
            }
            for it in cand.items where used[it.bundleID] == nil { used[it.bundleID] = usedAt(it.bundleID, it.pid) }
            guard let rule = Planner.nextToQuit(cand, rules: rules, skip: skip, lastUsed: used) else {
                if !warnedNoCandidate {
                    add("Menu bar is \(verdict == .overflow ? "full" : "almost full"), but no app can be closed.", "warn")
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
                lastQuitAt = Date()
                if l.macOverflow {
                    overflowQuits += 1
                    count = 99   // one app per « arrow sighting; look again once the bar settles
                    // Apps stuck in the « arrow: restart them once there is room, so macOS puts them back in the bar.
                    let shown = Set(l.items.map(\.bundleID))
                    let auto = Set(rules.filter(\.autoQuit).map(\.bundleID))
                    stuck = cand.items.filter { !shown.contains($0.bundleID) && $0.bundleID != rule.bundleID && auto.contains($0.bundleID) }.map(\.bundleID)
                }
                quit.removeAll { $0.bundleID == rule.bundleID }
                quit.append(QuitRecord(bundleID: rule.bundleID, name: rule.name, path: path,
                                       width: width, date: Date()))
                add("\(rule.name) quit. Click Restart in the panel to bring it back.", "quit")
            } else {
                add("\(rule.name) did not quit within 8 seconds. Left running.", "warn")
                skip.insert(rule.bundleID)
            }
            save()
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refresh()
            count += 1
        }
        if verdict == .ok { add("Menu bar has room again (\(Int(Planner.free(layout ?? BarLayout(rightMin: 0, maxX: 0, items: [])))) pt free).", "info") }
    }

    /// macOS's « arrow is up: some app icons did not fit. Close the allowed app used longest ago, then restart the hidden apps
    /// so macOS puts them back in the bar (it never pulls them out by itself). If only Apple icons are hidden, do nothing.
    private func fixArrow() async {
        guard let l = layout else { return }
        arrowFixes = arrowFixes.filter { Date().timeIntervalSince($0) < 300 }
        guard arrowFixes.count < 2 else { noFixUntil = Date().addingTimeInterval(300); add("The « arrow is still there after 2 tries. Roomy will try again in 5 minutes.", "warn"); return }
        let shown = Set(l.items.map(\.bundleID))
        let hiddenApps = rules.filter { !shown.contains($0.bundleID) && !$0.bundleID.hasPrefix("com.apple.") && $0.bundleID != ownID }
            .compactMap { r in NSRunningApplication.runningApplications(withBundleIdentifier: r.bundleID).first.map { (r, $0) } }
        guard !hiddenApps.isEmpty else { return }   // only Apple items behind the arrow: closing apps would not help
        arrowFixes.append(Date())
        busy = true; defer { busy = false }
        let hiddenIDs = Set(hiddenApps.map(\.0.bundleID))
        var used = lastUsed
        for it in l.items where used[it.bundleID] == nil { used[it.bundleID] = usedAt(it.bundleID, it.pid) }
        var skip = Set<String>([ownID]).union(justLaunched.keys).union(hiddenIDs)
        skip.formUnion(rules.filter { !$0.autoQuit }.map(\.bundleID))
        if let rule = Planner.nextToQuit(l, rules: rules, skip: skip, lastUsed: used),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID).first {
            let width = l.items.first { $0.bundleID == rule.bundleID }?.width ?? 30
            let path = rule.path ?? app.bundleURL?.path
            add("\(hiddenApps.map(\.0.name).joined(separator: ", ")) did not fit (macOS put it behind the « arrow). Closing \(rule.name), used longest ago.", "quit")
            app.terminate()
            var w = 0.0
            while !app.isTerminated, w < 8 { try? await Task.sleep(nanoseconds: 250_000_000); w += 0.25 }
            if app.isTerminated {
                quit.removeAll { $0.bundleID == rule.bundleID }
                quit.append(QuitRecord(bundleID: rule.bundleID, name: rule.name, path: path, width: width, date: Date()))
                save()
            }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for (r, a) in hiddenApps {
            guard let url = a.bundleURL else { continue }
            add("Restarting \(r.name) so macOS shows it in the bar.", "restore")
            a.terminate()
            var w = 0.0
            while !a.isTerminated, w < 6 { try? await Task.sleep(nanoseconds: 250_000_000); w += 0.25 }
            let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.addsToRecentItems = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        lastQuitAt = Date()
        await refresh()
    }

    private func restartStuck() async {
        let ids = stuck; stuck = []
        guard Scanner.sawOverflow else { return }      // macOS already moved them back
        busy = true; defer { busy = false }
        for id in ids {
            guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first, let url = a.bundleURL else { continue }
            add("\(a.localizedName ?? id) was stuck behind the « arrow. Restarting it so it shows in the bar.", "restore")
            a.terminate()
            var w = 0.0
            while !a.isTerminated, w < 6 { try? await Task.sleep(nanoseconds: 250_000_000); w += 0.25 }
            let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.addsToRecentItems = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        lastQuitAt = Date()   // give macOS time to settle before judging the bar again
        await refresh()
    }

    private func restoreOne() async {
        guard let l = layout, let rec = Planner.nextToRestore(l, rules: rules, quit: quit, margin: margin) else { return }
        busy = true; defer { busy = false }
        guard Date() > noRestoreUntil else { return }
        add("There is room again. Restarting \(rec.name).", "restore")
        lastRestoreAt = Date()
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
        if let v = try? e.encode(hiddenByGuard) { d.set(v, forKey: "hiddenByGuard") }
        d.set(guardOn, forKey: "guardOn"); d.set(autoRestore, forKey: "autoRestore"); d.set(margin, forKey: "margin")
    }

    private func load() {
        let x = JSONDecoder()
        if let v = d.data(forKey: "rules"), let r = try? x.decode([Rule].self, from: v) { rules = r }
        if let v = d.data(forKey: "quit"), let r = try? x.decode([QuitRecord].self, from: v) { quit = r }
        if let v = d.data(forKey: "log"), let r = try? x.decode([LogEntry].self, from: v) { log = r }
        if let v = d.data(forKey: "hiddenByGuard"), let r = try? x.decode([HiddenRecord].self, from: v) { hiddenByGuard = r }
        if !Prefs.shared.hidingOn { hiddenByGuard = [] }
        if let m = d.dictionary(forKey: "lastUsed") as? [String: Double] { lastUsed = m.mapValues { Date(timeIntervalSince1970: $0) } }
        if d.object(forKey: "guardOn") != nil { guardOn = d.bool(forKey: "guardOn") }
        if d.object(forKey: "autoRestore") != nil { autoRestore = d.bool(forKey: "autoRestore") }
        if d.object(forKey: "margin") != nil { margin = d.double(forKey: "margin") }
    }
}
