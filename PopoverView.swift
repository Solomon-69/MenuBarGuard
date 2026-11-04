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
    var openSettings: () -> Void = {}
    @State private var tab: Tab = .apps
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(engine: Engine, showIntro: @escaping () -> Void, quitApp: @escaping () -> Void,
         openSettings: @escaping () -> Void = {}, tab: String = "Apps") {
        self.engine = engine; self.showIntro = showIntro; self.quitApp = quitApp; self.openSettings = openSettings
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
        .animation(.spring(duration: 0.38, bounce: 0), value: shown)
        .animation(.spring(duration: 0.3, bounce: 0), value: tab)
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
                Text("Roomy").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(statusLine).font(.system(size: 11)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            SmoothSwitch(isOn: engine.guardOn, title: "Roomy on", tint: guardAccent) { engine.guardOn = $0 }
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
                .animation(.spring(duration: 0.5, bounce: 0), value: used)
            }
            .frame(height: 8)
            HStack {
                Text("\((l?.items.filter { $0.bundleID != Bundle.main.bundleIdentifier }.count) ?? 0) menu bar apps").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("Acts below \(Int(engine.margin)) pt free").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Apps and Log (shared with the Settings window)

    private var appsTab: some View { PriorityList(engine: engine) }
    private var logTab: some View { LogList(engine: engine) }

    // MARK: Settings

    private var settingsTab: some View {
        VStack(spacing: 8) {
            setting("Bring apps back automatically", "When there is room again, Roomy restarts what it closed.") {
                SmoothSwitch(isOn: engine.autoRestore, title: "Auto restore", tint: guardAccent) { engine.autoRestore = $0 }
            }
            setting("Open at login", "Start Roomy when you sign in.") {
                SmoothSwitch(isOn: engine.openAtLogin, title: "Open at login", tint: guardAccent) { engine.openAtLogin = $0 }
            }
            setting("Act when free space is below", "\(Int(engine.margin)) pt, about \(max(1, Int(engine.margin / 36))) icon(s).") {
                Stepper("", value: $engine.margin, in: 20...120, step: 10).labelsHidden()
            }
            setting("Accessibility access", engine.trusted ? "Granted. Roomy can see the menu bar." : "Needed to see where icons are. Nothing is recorded.") {
                if engine.trusted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(guardAccent)
                } else {
                    Button("Allow…") { Scanner.askAccessibility() }.buttonStyle(MiniButton())
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
            Button(action: openSettings) { Label("Settings…", systemImage: "gearshape") }.buttonStyle(MiniButton())
                .help("Hidden sections, Ice Bar, menu bar look, hotkeys and more")
            Spacer()
            Button("Quit Roomy", action: quitApp).buttonStyle(MiniButton())
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
