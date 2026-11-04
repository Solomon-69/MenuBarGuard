// SettingsPanes.swift: Menu Bar Layout, Menu Bar Look, Hotkeys and Auto-quit pages.
import AppKit
import SwiftUI

// MARK: Layout

struct LayoutPane: View {
    @ObservedObject var engine: Engine
    @ObservedObject var prefs: Prefs
    @ObservedObject var sections: SectionController
    @ObservedObject var images: ItemImages
    let actions: SettingsActions
    @State private var target: BarSection?
    @State private var pendingOffset: Int?

    var body: some View {
        let d = sections.dividers
        let own = Bundle.main.bundleIdentifier ?? ""
        let entries = engine.entries.filter { $0.bundleID != own && $0.x > -20_000 }
        VStack(alignment: .leading, spacing: 4) {
            PaneTitle(title: "Menu Bar Layout", detail: "Drag icons between the sections. No need to hold Command: Roomy moves the real icon for you.")
            if sections.orderProblem {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("The shield is left of the ‹ divider, so nothing is hidden yet (it would hide the shield too).")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Fix it", action: actions.arrange).buttonStyle(MiniButton())
                }
                .padding(10).card().padding(.bottom, 8)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
            ForEach([BarSection.visible, .hidden, .alwaysHidden]) { s in
                if s != .alwaysHidden || prefs.alwaysHiddenOn {
                    zone(s, entries.filter { SectionLogic.section($0, d) == s })
                }
            }
            HStack {
                Button { actions.rescan() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(MiniButton())
                Button { actions.arrange() } label: { Label("Put dividers in place", systemImage: "wand.and.stars") }.buttonStyle(MiniButton())
                    .help("Shield next to Apple's icons, ‹ just left of it, « left of everything.")
                Text(prefs.hidingOn ? "Tip: right-click an icon here for “Move to”." : "Turn on hiding in General to use sections.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)
            spacing
        }
    }

    private func zone(_ s: BarSection, _ items: [BarEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text("\(items.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if items.isEmpty { Text("Drop icons here").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8) }
                    ForEach(items) { e in chip(e, current: s) }
                }
                .padding(8)
                .animation(.spring(duration: 0.3, bounce: 0.12), value: items.map(\.id))
            }
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(target == s ? guardAccent.opacity(0.14) : Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(target == s ? guardAccent : Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: target == s ? [4, 3] : [])))
            .animation(.spring(duration: 0.25), value: target)
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, let e = engine.entries.first(where: { $0.id == id }) else { return false }
                actions.move(e, s); return true
            } isTargeted: { t in target = t ? s : (target == s ? nil : target) }
        }
        .padding(.bottom, 8)
    }

    private func chip(_ e: BarEntry, current: BarSection) -> some View {
        HStack(spacing: 5) {
            if let img = images.image(e) { Image(nsImage: img).interpolation(.high).frame(width: min(e.width, 44), height: 22) }
            else { AppIcon(bundleID: e.bundleID, pid: e.pid).frame(width: 18, height: 18) }
            Text(e.appName).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 8).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .help(e.title)
        .draggable(e.id) {
            HStack { AppIcon(bundleID: e.bundleID, pid: e.pid).frame(width: 18, height: 18); Text(e.appName).font(.system(size: 11.5)) }
                .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        }
        .contextMenu {
            ForEach(BarSection.allCases.filter { $0 != current && ($0 != .alwaysHidden || prefs.alwaysHiddenOn) }) { s in
                Button("Move to \(s.title)") { actions.move(e, s) }
            }
        }
    }

    private var spacing: some View {
        let shown = pendingOffset ?? prefs.spacingOffset
        return SettingsGroup(title: "ICON SPACING") {
            SettingRow(title: "Space between icons", detail: "Tighter fits more icons next to the notch. Apps must relaunch to pick it up.") {
                HStack(spacing: 8) {
                    Text("Tight").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(shown) }, set: { pendingOffset = Int($0.rounded()) }),
                           in: Double(Spacing.range.lowerBound)...Double(Spacing.range.upperBound), step: 1).frame(width: 160)
                    Text("Wide").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(shown == 0 ? "Default" : (shown > 0 ? "+\(shown)" : "\(shown)")).font(.system(size: 11, design: .monospaced)).frame(width: 54)
                }
            }
            Divided()
            HStack(spacing: 8) {
                Spacer()
                Button("Reset") { pendingOffset = 0 }.buttonStyle(MiniButton())
                Button("Apply") { prefs.spacingOffset = shown; actions.applySpacing(false); pendingOffset = nil }.buttonStyle(MiniButton())
                Button("Apply and relaunch apps") { prefs.spacingOffset = shown; actions.applySpacing(true); pendingOffset = nil }.buttonStyle(MiniButton())
                    .help("Politely quits and reopens menu bar apps (not locked ones). Apple's icons change after you log out and in.")
            }
            .padding(10)
        }
    }
}

// MARK: Look

struct LookPane: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        let c = prefs.look
        VStack(alignment: .leading, spacing: 4) {
            PaneTitle(title: "Menu Bar Look", detail: "Tint, shadow, border and shape for the menu bar. Menus and icons stay on top.")
            preview(c)
            SettingsGroup {
                SwitchRow(title: "Custom menu bar look", isOn: c.on) { v in prefs.look.on = v }
                Divided()
                SettingRow(title: "Tint") {
                    SlidingSegments(options: TintKind.allCases, label: \.rawValue, selection: c.tint) { prefs.look.tint = $0 }
                }
                if c.tint == .solid {
                    Divided()
                    SettingRow(title: "Colour") { ColorPicker("", selection: color(\.solid)).labelsHidden() }
                }
                if c.tint == .gradient {
                    Divided()
                    SettingRow(title: "Colours", detail: "Left to right.") {
                        HStack { ColorPicker("", selection: color(\.from)).labelsHidden(); ColorPicker("", selection: color(\.to)).labelsHidden() }
                    }
                }
                Divided()
                SwitchRow(title: "Shadow", isOn: c.shadow) { v in prefs.look.shadow = v }
                Divided()
                SwitchRow(title: "Border", isOn: c.border) { v in prefs.look.border = v }
                if c.border {
                    Divided()
                    SettingRow(title: "Border colour and width") {
                        HStack {
                            ColorPicker("", selection: color(\.borderColor)).labelsHidden()
                            Stepper("\(Int(c.borderWidth)) pt", value: $prefs.look.borderWidth, in: 1...4, step: 1).font(.system(size: 12))
                        }
                    }
                }
                Divided()
                SettingRow(title: "Shape", detail: "Split: one piece for the app menus, one for the icons.") {
                    SlidingSegments(options: BarShape.allCases, label: \.rawValue, selection: c.shape) { prefs.look.shape = $0 }
                }
                if c.shape != .full {
                    Divided()
                    SettingRow(title: "Corner roundness") {
                        Slider(value: $prefs.look.radius, in: 2...16, step: 1).frame(width: 160)
                    }
                }
                Divided()
                SwitchRow(title: "Also on full-screen spaces", isOn: c.fullScreen) { v in prefs.look.fullScreen = v }
            }
            .animation(.spring(duration: 0.3, bounce: 0.1), value: c)
        }
    }

    private func color(_ k: WritableKeyPath<LookConfig, RGBA>) -> Binding<Color> {
        Binding(get: { prefs.look[keyPath: k].color }, set: { prefs.look[keyPath: k] = RGBA($0) })
    }

    private func preview(_ c: LookConfig) -> some View {
        let m = LookModel()
        m.config = c; m.config.on = true
        m.width = 460; m.height = 26; m.appMenusMaxX = 150; m.iconsMinX = 320; m.notch = 200...260
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.55), Color(red: 0.55, green: 0.4, blue: 0.5)], startPoint: .leading, endPoint: .trailing)
            if c.on { LookView(model: m) }
            HStack(spacing: 12) {
                Text("Finder  File  Edit  View").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                Spacer()
                ForEach(["wifi", "battery.75", "magnifyingglass"], id: \.self) { Image(systemName: $0).foregroundStyle(.white).font(.system(size: 11)) }
            }
            .padding(.horizontal, 12).frame(width: 460, height: 26)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 60, height: 26).offset(x: 200)
        }
        .frame(width: 460, height: 70, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 12)
    }
}

// MARK: Hotkeys

struct HotkeysPane: View {
    @ObservedObject var prefs: Prefs
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PaneTitle(title: "Hotkeys", detail: "Keyboard shortcuts that work in every app. Click Record, then press the keys (with ⌘, ⌥ or ⌃). Esc cancels.")
            SettingsGroup {
                SwitchRow(title: "Use hotkeys", detail: "Off by default. Shortcuts only work while this is on.", isOn: prefs.hotkeysOn) { prefs.hotkeysOn = $0 }
            }
            SettingsGroup {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element) { i, a in
                    if i > 0 { Divided() }
                    SettingRow(title: a.title, detail: problem(a)) { HotkeyRecorder(action: a, prefs: prefs) }
                }
            }
        }
    }
    private func problem(_ a: HotkeyAction) -> String? {
        guard let s = Hotkeys.shared.status[a.rawValue], s != 0 else { return nil }
        return "Another app already uses this shortcut. Pick a different one."
    }
}

// MARK: Auto-quit

struct AutoQuitPane: View {
    @ObservedObject var engine: Engine
    @ObservedObject private var prefs = Prefs.shared
    @State private var showLog = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneTitle(title: "Auto-quit", detail: "If the menu bar is still full after hiding icons, Roomy politely quits the lowest apps you allowed, and brings them back when there is room.")
            SettingsGroup {
                SwitchRow(title: "Show Roomy in the menu bar", detail: "Off: Roomy keeps working without an icon, so it takes no space. To get Settings back, open Roomy again from Applications.", isOn: prefs.showIcon) { prefs.showIcon = $0 }
                Divided()
                SwitchRow(title: "Hide icons first when the bar is full", detail: "Roomy moves the lowest apps behind the shield (they keep running). Click the shield to see them.", isOn: prefs.autoHide) { prefs.autoHide = $0 }
                Divided()
                SwitchRow(title: "Bring apps back automatically", isOn: engine.autoRestore) { engine.autoRestore = $0 }
                Divided()
                SettingRow(title: "Act when free space is below", detail: "\(Int(engine.margin)) pt, about \(max(1, Int(engine.margin / 36))) icon(s).") {
                    Stepper("", value: $engine.margin, in: 20...120, step: 10).labelsHidden()
                }
            }
            SlidingSegments(options: [false, true], label: { $0 ? "Log" : "Priority list" }, selection: showLog) { showLog = $0 }
                .padding(.bottom, 4)
            Group { if showLog { LogList(engine: engine) } else { PriorityList(engine: engine) } }
                .frame(height: 360)
        }
    }
}
