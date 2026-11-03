// PopoverView.swift: the panel that opens under the menu bar icon.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

let guardAccent = Color(red: 0.13, green: 0.60, blue: 0.55)

private enum Tab: String, CaseIterable { case apps = "Apps", log = "Log", settings = "Settings" }

struct PopoverView: View {
    @ObservedObject var engine: Engine
    var showIntro: () -> Void
    var quitApp: () -> Void
    @State private var tab: Tab = .apps
    @State private var shown = false
    @State private var dragging: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(engine: Engine, showIntro: @escaping () -> Void, quitApp: @escaping () -> Void, tab: String = "Apps") {
        self.engine = engine; self.showIntro = showIntro; self.quitApp = quitApp
        _tab = State(initialValue: Tab(rawValue: tab) ?? .apps)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            meter
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().focusEffectDisabled()
            Group {
                switch tab {
                case .apps: appsTab
                case .log: logTab
                case .settings: settingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            footer
        }
        .padding(16).padding(.top, 6)
        .frame(width: 380, height: 560)
        .modifier(PopoverBackdrop())
        .tint(guardAccent)
        .scaleEffect(shown || reduceMotion ? 1 : 0.97)
        .opacity(shown || reduceMotion ? 1 : 0.0)
        .animation(.spring(duration: 0.42, bounce: 0.18), value: shown)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: tab)
        .onChange(of: engine.openCount) { _, _ in shown = false; DispatchQueue.main.async { shown = true } }
        .onAppear { shown = true }
    }

    // MARK: Header + meter

    private var statusColor: Color {
        if !engine.trusted { return .orange }
        switch engine.verdict { case .ok: return guardAccent; case .tight: return .orange; case .overflow: return .red }
    }

    private var statusLine: String {
        guard engine.trusted else { return "Needs Accessibility access to see the menu bar." }
        guard let l = engine.layout else { return "Looking at the menu bar…" }
        let free = Int(Planner.free(l))
        switch engine.verdict {
        case .ok: return "All icons visible · \(free) pt to spare"
        case .tight: return "Almost full · only \(free) pt left"
        case .overflow: return "\(Planner.hidden(l).count) icon(s) hidden behind the notch"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.verdict == .ok && engine.trusted ? "shield.lefthalf.filled" : "exclamationmark.shield.fill")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(statusColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Menu Bar Guard").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(statusLine).font(.system(size: 11)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            SmoothSwitch(isOn: engine.guardOn, title: "Guard on", tint: guardAccent) { engine.guardOn = $0 }
        }
    }

    /// A strip of the free icon area: how much of it is used by icons, how much is left.
    private var meter: some View {
        let l = engine.layout
        let cap = max(1, (l?.maxX ?? 1) - (l?.rightMin ?? 0))
        let free = l.map { Planner.free($0) } ?? 0
        let used = l == nil ? 0 : min(1, max(0, 1 - free / cap))
        return VStack(spacing: 5) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    Capsule().fill(statusColor.gradient).frame(width: max(8, g.size.width * used))
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1.5)
                        .offset(x: g.size.width * min(1, engine.margin / cap))
                        .opacity(0)
                }
                .animation(.spring(duration: 0.5, bounce: 0.12), value: used)
            }
            .frame(height: 8)
            HStack {
                Text("\(l?.items.count ?? 0) menu bar apps").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("Acts below \(Int(engine.margin)) pt free").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Apps

    private var appsTab: some View {
        VStack(spacing: 8) {
            if !engine.quit.isEmpty { closedBox }
            Text("Top = keep longest. Guard closes from the bottom up, only apps with Auto-quit on.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(engine.rules) { r in
                        row(r)
                            .onDrag { dragging = r.bundleID; return NSItemProvider(object: r.bundleID as NSString) }
                            .onDrop(of: [.text], delegate: ReorderDrop(item: r, engine: engine, dragging: $dragging))
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.3, bounce: 0.1), value: engine.rules.map(\.bundleID))
            }
        }
    }

    private var closedBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Closed by Guard", systemImage: "moon.zzz.fill").font(.system(size: 11, weight: .semibold))
                Spacer()
                if engine.quit.count > 1 { Button("Restart all") { engine.restartAll() }.buttonStyle(MiniButton()) }
            }
            ForEach(engine.quit) { q in
                HStack {
                    icon(q.path ?? engine.appPath(bundleID: q.bundleID)).frame(width: 20, height: 20)
                    Text(q.name).font(.system(size: 12))
                    Spacer()
                    Button("Restart") { engine.restart(q) }.buttonStyle(MiniButton())
                }
            }
        }
        .padding(10).card()
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func row(_ r: Rule) -> some View {
        let running = engine.layout?.items.contains { $0.bundleID == r.bundleID }
            ?? !NSRunningApplication.runningApplications(withBundleIdentifier: r.bundleID).isEmpty
        let closed = engine.quit.contains { $0.bundleID == r.bundleID }
        return HStack(spacing: 10) {
            icon(engine.appPath(r)).frame(width: 28, height: 28).opacity(running ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.name).font(.system(size: 12.5, weight: .medium))
                Text(closed ? "Closed by Guard" : running ? "In the menu bar" : "Not running")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { engine.setNever(r.bundleID, !r.neverQuit) } label: {
                Image(systemName: r.neverQuit ? "lock.fill" : "lock.open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(r.neverQuit ? guardAccent : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(r.neverQuit ? guardAccent.opacity(0.16) : Color.clear))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).focusEffectDisabled().help("Never quit this app")
            VStack(spacing: 1) {
                SmoothSwitch(isOn: r.autoQuit, title: "Auto-quit \(r.name)", tint: guardAccent, width: 34) { engine.setAuto(r.bundleID, $0) }
                    .opacity(r.neverQuit ? 0.3 : 1).allowsHitTesting(!r.neverQuit)
                Text("Auto-quit").font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .card()
    }

    private func icon(_ path: String?) -> some View {
        Image(nsImage: path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
            .resizable().interpolation(.high)
    }

    // MARK: Log

    private var logTab: some View {
        VStack(spacing: 8) {
            if engine.log.isEmpty {
                Spacer()
                Text("Nothing yet. When Guard closes or restarts an app, it is written here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(engine.log.prefix(80)) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: symbol(e.kind)).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(color(e.kind)).frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                                    Text(e.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8).card()
                        }
                    }
                }
                HStack { Spacer(); Button("Clear log") { engine.clearLog() }.buttonStyle(MiniButton()) }
            }
        }
    }

    private func symbol(_ k: String) -> String {
        switch k { case "quit": return "power"; case "restore": return "arrow.clockwise"; case "warn": return "exclamationmark.triangle.fill"; default: return "info.circle" }
    }
    private func color(_ k: String) -> Color {
        switch k { case "quit": return .red; case "restore": return guardAccent; case "warn": return .orange; default: return .secondary }
    }

    // MARK: Settings

    private var settingsTab: some View {
        VStack(spacing: 8) {
            setting("Bring apps back automatically", "When there is room again, Guard restarts what it closed.") {
                SmoothSwitch(isOn: engine.autoRestore, title: "Auto restore", tint: guardAccent) { engine.autoRestore = $0 }
            }
            setting("Open at login", "Start Menu Bar Guard when you sign in.") {
                SmoothSwitch(isOn: engine.openAtLogin, title: "Open at login", tint: guardAccent) { engine.openAtLogin = $0 }
            }
            setting("Act when free space is below", "\(Int(engine.margin)) pt, about \(max(1, Int(engine.margin / 36))) icon(s).") {
                Stepper("", value: $engine.margin, in: 20...120, step: 10).labelsHidden()
            }
            setting("Accessibility access", engine.trusted ? "Granted. Guard can see the menu bar." : "Needed to see where icons are. Nothing is recorded.") {
                if engine.trusted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(guardAccent)
                } else {
                    Button("Allow…") { _ = Scanner.trusted(prompt: true) }.buttonStyle(MiniButton())
                }
            }
            Button("Show the welcome screens again") { showIntro() }.buttonStyle(MiniButton()).padding(.top, 4)
        }
    }

    private func setting<T: View>(_ title: String, _ detail: String, @ViewBuilder _ control: () -> T) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(10).card()
    }

    private var footer: some View {
        HStack {
            Text("Quits politely, never forces.").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button("Quit Menu Bar Guard", action: quitApp).buttonStyle(MiniButton())
        }
    }
}

extension View {
    func card() -> some View {
        background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

struct MiniButton: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(hover ? 0.14 : 0.08)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}


/// Drag one row over another to swap places, live.
struct ReorderDrop: DropDelegate {
    let item: Rule
    let engine: Engine
    @Binding var dragging: String?
    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != item.bundleID,
              let from = engine.rules.firstIndex(where: { $0.bundleID == d }),
              let to = engine.rules.firstIndex(where: { $0.bundleID == item.bundleID }) else { return }
        engine.move(IndexSet(integer: from), to > from ? to + 1 : to)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
