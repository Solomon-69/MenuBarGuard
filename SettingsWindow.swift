// SettingsWindow.swift: the Settings window (sidebar: General, Menu Bar Layout, Menu Bar Look,
// Hotkeys, Auto-quit, About) plus the shared controls used on every page.
import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", layout = "Menu Bar Layout", look = "Menu Bar Look", hotkeys = "Hotkeys", autoQuit = "Auto-quit", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .look: return "paintbrush"
        case .hotkeys: return "command"
        case .autoQuit: return "power"
        case .about: return "info.circle"
        }
    }
}

/// What the Settings window can ask the app to do.
struct SettingsActions {
    var move: (BarEntry, BarSection) -> Void = { _, _ in }
    var arrange: () -> Void = {}
    var rescan: () -> Void = {}
    var showIntro: () -> Void = {}
    var askAccessibility: () -> Void = {}
    var askScreenRecording: () -> Void = {}
    var applySpacing: (_ relaunch: Bool) -> Void = { _ in }
}

@MainActor final class SettingsWindowController {
    private var window: NSWindow?
    let nav = SettingsNav()

    func show(_ content: AnyView, pane: SettingsPane? = nil, activate: Bool = true) {
        if let pane { nav.pane = pane }
        if window == nil {
            let host = NSHostingController(rootView: content)
            let w = NSWindow(contentViewController: host)
            w.title = "Menu Bar Guard Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 760, height: 540))
            w.minSize = NSSize(width: 680, height: 460)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // A real Settings window is the one place Menu Bar Guard comes to the front (you asked for it).
        guard activate else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var isShown: Bool { window?.isVisible == true }
    var windowNumber: Int { window?.windowNumber ?? 0 }

    /// Tests only: the real window, placed off screen and never brought forward (for a quiet screenshot).
    func showOffscreen(_ content: AnyView, pane: SettingsPane?, dark: Bool) {
        if window == nil { show(content, pane: pane, activate: false) }
        if let pane { nav.pane = pane }
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window?.setFrameOrigin(NSPoint(x: -5000, y: 200))
        window?.orderFrontRegardless()
    }

    func close() { window?.orderOut(nil) }
}

@MainActor final class SettingsNav: ObservableObject { @Published var pane: SettingsPane = .general }

struct SettingsView: View {
    @ObservedObject var nav: SettingsNav
    @ObservedObject var engine: Engine
    @ObservedObject var prefs: Prefs
    @ObservedObject var sections: SectionController
    @ObservedObject var images: ItemImages
    let actions: SettingsActions

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { nav.pane }, set: { if let p = $0 { nav.pane = p } })) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            ScrollView { page.padding(24).frame(maxWidth: .infinity, alignment: .topLeading) }
                .id(nav.pane)
                .transition(.opacity)
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: nav.pane)
        .tint(guardAccent)
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder private var page: some View {
        switch nav.pane {
        case .general: GeneralPane(engine: engine, prefs: prefs, images: images, actions: actions)
        case .layout: LayoutPane(engine: engine, prefs: prefs, sections: sections, images: images, actions: actions)
        case .look: LookPane(prefs: prefs)
        case .hotkeys: HotkeysPane(prefs: prefs)
        case .autoQuit: AutoQuitPane(engine: engine)
        case .about: AboutPane()
        }
    }
}

// MARK: Shared pieces

struct PaneTitle: View {
    let title: String, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

/// A settings card: rows separated by thin lines.
struct SettingsGroup<C: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(spacing: 0) { content() }.card()
        }
        .padding(.bottom, 10)
    }
}

struct SettingRow<T: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: () -> T
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

/// On/off row with the glitch-free switch.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    let isOn: Bool
    let set: (Bool) -> Void
    var body: some View {
        SettingRow(title: title, detail: detail) { SmoothSwitch(isOn: isOn, title: title, tint: guardAccent, width: 36, onChange: set) }
    }
}

/// Segmented choice whose highlight slides with a spring (never jumps).
struct SlidingSegments<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    let selection: T
    let set: (T) -> Void
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Text(label(o))
                    .font(.system(size: 12, weight: o == selection ? .semibold : .regular))
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .foregroundStyle(o == selection ? Color.white : Color.primary)
                    .background {
                        if o == selection {
                            Capsule().fill(guardAccent).matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) { set(o) } }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }
}

struct Divided: View { var body: some View { Divider().padding(.leading, 12) } }

// MARK: General

struct GeneralPane: View {
    @ObservedObject var engine: Engine
    @ObservedObject var prefs: Prefs
    @ObservedObject var images: ItemImages
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PaneTitle(title: "General", detail: "Every extra below is off until you switch it on. With hiding on: click the shield to see hidden icons, Option-click for the always-hidden ones too, right-click for the panel.")
            SettingsGroup(title: "HIDING") {
                SwitchRow(title: "Hide icons left of the divider", detail: "Icons left of ‹ stay hidden until you click the shield.", isOn: prefs.hidingOn) { prefs.hidingOn = $0 }
                Divided()
                SwitchRow(title: "Always-hidden section", detail: "Icons left of « only show with Option-click or its hotkey.", isOn: prefs.alwaysHiddenOn) { prefs.alwaysHiddenOn = $0 }
                Divided()
                SwitchRow(title: "Show divider icons", detail: "The small ‹ and « marks while sections are shown.", isOn: prefs.showDividers) { prefs.showDividers = $0 }
            }
            SettingsGroup(title: "ICE BAR") {
                SwitchRow(title: "Show hidden icons in a bar under the menu bar", detail: "So nothing ends up behind the notch. Click an icon there to open its menu.", isOn: prefs.useIceBar) { prefs.useIceBar = $0 }
                Divided()
                SwitchRow(title: "Only on screens with a notch", isOn: prefs.iceBarNotchOnly) { prefs.iceBarNotchOnly = $0 }
            }
            SettingsGroup(title: "SHOW HIDDEN ICONS WHEN") {
                SwitchRow(title: "Clicking empty menu bar space", isOn: prefs.showOnClick) { prefs.showOnClick = $0 }
                Divided()
                SwitchRow(title: "Hovering over empty menu bar space", isOn: prefs.showOnHover) { prefs.showOnHover = $0 }
                Divided()
                SwitchRow(title: "Scrolling or swiping on the menu bar", detail: "Up or right shows, down or left hides.", isOn: prefs.showOnScroll) { prefs.showOnScroll = $0 }
            }
            SettingsGroup(title: "SEARCH") {
                SwitchRow(title: "Search menu bar icons", detail: "Type to find any icon, Enter opens it. Opens with its hotkey (set one in Hotkeys).", isOn: prefs.searchOn) { prefs.searchOn = $0 }
            }
            SettingsGroup(title: "HIDE AGAIN") {
                SwitchRow(title: "Hide again automatically", isOn: prefs.autoRehide) { prefs.autoRehide = $0 }
                Divided()
                SettingRow(title: "After", detail: "Waits while the pointer is on the menu bar.") {
                    Stepper("\(Int(prefs.rehideDelay)) seconds", value: $prefs.rehideDelay, in: 3...120, step: 1).font(.system(size: 12))
                }
                Divided()
                SwitchRow(title: "When you switch to another app", isOn: prefs.rehideOnAppSwitch) { prefs.rehideOnAppSwitch = $0 }
            }
            SettingsGroup(title: "APP") {
                SwitchRow(title: "Guard on", detail: "Watch the menu bar: hide first, then quit low-priority apps if still full.", isOn: engine.guardOn) { engine.guardOn = $0 }
                Divided()
                SwitchRow(title: "Open at login", isOn: engine.openAtLogin) { engine.openAtLogin = $0 }
            }
            SettingsGroup(title: "PERMISSIONS") {
                SettingRow(title: "Accessibility", detail: "Needed to see, open and move menu bar icons.") {
                    permission(engine.trusted, actions.askAccessibility)
                }
                Divided()
                SettingRow(title: "Screen Recording (optional)", detail: "Shows real pictures of icons in the Ice Bar and search. Without it: app icon and name.") {
                    permission(images.allowed, actions.askScreenRecording)
                }
                Divided()
                SettingRow(title: "Welcome screens") { Button("Show again", action: actions.showIntro).buttonStyle(MiniButton()) }
            }
        }
    }

    @ViewBuilder private func permission(_ ok: Bool, _ ask: @escaping () -> Void) -> some View {
        if ok { Label("Allowed", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(guardAccent) }
        else { Button("Allow…", action: ask).buttonStyle(MiniButton()) }
    }
}

// MARK: About

struct AboutPane: View {
    var body: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Menu Bar Guard").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Version \(v)").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Hides the menu bar icons you rarely need, and if the bar is still full, politely quits the apps you allowed.")
                .font(.system(size: 12)).multilineTextAlignment(.center).frame(maxWidth: 380)
            Text("Free and open source, MIT licence. Hiding features inspired by the behaviour of Ice by Jordan Baird; no Ice code is used.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }
}
