// Prefs.swift: every setting added in 1.1 (hiding, Ice Bar, triggers, look, spacing, hotkeys), saved in UserDefaults.
// Every new feature is OFF by default; each is switched on only from its own toggle in Settings.
import AppKit
import Combine
import SwiftUI

enum TintKind: String, Codable, CaseIterable { case none = "None", solid = "Solid", gradient = "Gradient" }
enum BarShape: String, Codable, CaseIterable { case full = "Full", rounded = "Rounded", split = "Split" }

/// Plain RGBA so colours can be saved.
struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ c: Color) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .gray
        r = Double(n.redComponent); g = Double(n.greenComponent); b = Double(n.blueComponent); a = Double(n.alphaComponent)
    }
}

struct LookConfig: Codable, Equatable {
    var on = false
    var tint: TintKind = .solid
    var solid = RGBA(r: 0.13, g: 0.60, b: 0.55, a: 0.35)
    var from = RGBA(r: 0.13, g: 0.60, b: 0.55, a: 0.45)
    var to = RGBA(r: 0.35, g: 0.30, b: 0.75, a: 0.45)
    var shadow = false
    var border = false
    var borderColor = RGBA(r: 1, g: 1, b: 1, a: 0.35)
    var borderWidth: Double = 1
    var shape: BarShape = .full
    var radius: Double = 9
    var fullScreen = false
}

@MainActor final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var showIcon: Bool { didSet { d.set(showIcon, forKey: "showIcon") } }
    /// Full bar: hide the lowest-priority icons first (Command-drag them left of the divider), quit apps only if still full.
    @Published var autoHide: Bool { didSet { d.set(autoHide, forKey: "autoHide") } }
    @Published var hidingOn: Bool { didSet { d.set(hidingOn, forKey: "hidingOn") } }
    @Published var alwaysHiddenOn: Bool { didSet { d.set(alwaysHiddenOn, forKey: "alwaysHiddenOn") } }
    @Published var showDividers: Bool { didSet { d.set(showDividers, forKey: "showDividers") } }
    @Published var useIceBar: Bool { didSet { d.set(useIceBar, forKey: "useIceBar") } }
    @Published var iceBarNotchOnly: Bool { didSet { d.set(iceBarNotchOnly, forKey: "iceBarNotchOnly") } }
    @Published var showOnHover: Bool { didSet { d.set(showOnHover, forKey: "showOnHover") } }
    @Published var showOnClick: Bool { didSet { d.set(showOnClick, forKey: "showOnClick") } }
    @Published var showOnScroll: Bool { didSet { d.set(showOnScroll, forKey: "showOnScroll") } }
    @Published var autoRehide: Bool { didSet { d.set(autoRehide, forKey: "autoRehide") } }
    @Published var rehideDelay: Double { didSet { d.set(rehideDelay, forKey: "rehideDelay") } }
    @Published var rehideOnAppSwitch: Bool { didSet { d.set(rehideOnAppSwitch, forKey: "rehideOnAppSwitch") } }
    @Published var searchOn: Bool { didSet { d.set(searchOn, forKey: "searchOn") } }
    @Published var hotkeysOn: Bool { didSet { d.set(hotkeysOn, forKey: "hotkeysOn") } }
    @Published var spacingOffset: Int { didSet { d.set(spacingOffset, forKey: "spacingOffset") } }
    @Published var look: LookConfig { didSet { if let v = try? JSONEncoder().encode(look) { d.set(v, forKey: "look") } } }
    @Published var hotkeys: [String: HotkeyCombo] { didSet { if let v = try? JSONEncoder().encode(hotkeys) { d.set(v, forKey: "hotkeys") } } }

    private init() {
        let d = UserDefaults.standard
        func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        showIcon = b("showIcon", false)
        autoHide = b("autoHide", false)
        hidingOn = b("hidingOn", false)
        if d.object(forKey: "migrated131") == nil { autoHide = false; hidingOn = false; d.removeObject(forKey: "hiddenByGuard"); d.set(true, forKey: "migrated131") }
        // 1.3.2: Roomy works fully invisibly by default (no shield, no ‹ divider). Opening the app shows Settings.
        if d.object(forKey: "migrated132") == nil { showIcon = false; hidingOn = false; d.set(true, forKey: "migrated132") }  // 1.3.0: close old apps, never bury new ones
        alwaysHiddenOn = b("alwaysHiddenOn", false)
        showDividers = b("showDividers", true)
        useIceBar = b("useIceBar", false)
        iceBarNotchOnly = b("iceBarNotchOnly", true)
        showOnHover = b("showOnHover", false)
        showOnClick = b("showOnClick", false)
        showOnScroll = b("showOnScroll", false)
        autoRehide = b("autoRehide", true)
        rehideDelay = d.object(forKey: "rehideDelay") == nil ? 15 : d.double(forKey: "rehideDelay")
        rehideOnAppSwitch = b("rehideOnAppSwitch", true)
        searchOn = b("searchOn", false)
        hotkeysOn = b("hotkeysOn", false)
        spacingOffset = d.integer(forKey: "spacingOffset")
        look = d.data(forKey: "look").flatMap { try? JSONDecoder().decode(LookConfig.self, from: $0) } ?? LookConfig()
        hotkeys = d.data(forKey: "hotkeys").flatMap { try? JSONDecoder().decode([String: HotkeyCombo].self, from: $0) } ?? [:]
    }

    /// The Ice Bar is used on screens with a notch (or everywhere, if the user chose that).
    var iceBarActive: Bool {
        guard useIceBar else { return false }
        return !iceBarNotchOnly || NSScreen.screens.contains { $0.auxiliaryTopRightArea != nil }
    }
}
