// Hotkeys.swift: system-wide keyboard shortcuts (Carbon RegisterEventHotKey, no extra permission).
import AppKit
import Carbon.HIToolbox
import SwiftUI

enum HotkeyAction: String, CaseIterable, Identifiable {
    case toggleHidden, toggleAlways, search, toggleIceBar, toggleDividers, openPanel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggleHidden: return "Show or hide the hidden section"
        case .toggleAlways: return "Show or hide the always-hidden section"
        case .search: return "Search menu bar icons"
        case .toggleIceBar: return "Turn the Ice Bar on or off"
        case .toggleDividers: return "Show or hide the divider icons"
        case .openPanel: return "Open the Menu Bar Guard panel"
        }
    }
}

struct HotkeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonMods: UInt32
    var display: String

    init(keyCode: UInt32, carbonMods: UInt32, display: String) { self.keyCode = keyCode; self.carbonMods = carbonMods; self.display = display }

    /// From a key press in the recorder. Needs at least one of Command, Option or Control.
    init?(event e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command) || f.contains(.option) || f.contains(.control) else { return nil }
        var m: UInt32 = 0, s = ""
        if f.contains(.control) { m |= UInt32(controlKey); s += "⌃" }
        if f.contains(.option) { m |= UInt32(optionKey); s += "⌥" }
        if f.contains(.shift) { m |= UInt32(shiftKey); s += "⇧" }
        if f.contains(.command) { m |= UInt32(cmdKey); s += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 51: "Delete", 53: "Esc", 48: "Tab", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10"]
        s += names[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        self.init(keyCode: UInt32(e.keyCode), carbonMods: m, display: s)
    }
}

@MainActor final class Hotkeys {
    static let shared = Hotkeys()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    var perform: (HotkeyAction) -> Void = { _ in }
    /// Last registration result per action (0 = noErr). For the Settings screen and tests.
    private(set) var status: [String: Int32] = [:]
    private let ids: [HotkeyAction: UInt32] = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.enumerated().map { ($1, UInt32($0 + 1)) })

    func register(_ all: [String: HotkeyCombo]) {
        installHandler()
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs = [:]; status = [:]
        for a in HotkeyAction.allCases {
            guard let c = all[a.rawValue], let id = ids[a] else { continue }
            var ref: EventHotKeyRef?
            let hk = EventHotKeyID(signature: OSType(0x4D424721), id: id)        // 'MBG!'
            let err = RegisterEventHotKey(c.keyCode, c.carbonMods, hk, GetApplicationEventTarget(), 0, &ref)
            status[a.rawValue] = err
            if err == noErr, let ref { refs[id] = ref }
        }
    }

    func fire(id: UInt32) {
        guard let a = ids.first(where: { $0.value == id })?.key else { return }
        perform(a)
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.shared.fire(id: id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Click, then press the keys you want. Esc cancels, Delete clears.
struct HotkeyRecorder: View {
    let action: HotkeyAction
    @ObservedObject var prefs: Prefs
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        let combo = prefs.hotkeys[action.rawValue]
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Press keys…" : combo?.display ?? "Record")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 96).padding(.vertical, 5).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(recording ? guardAccent.opacity(0.22) : Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(recording ? guardAccent : Color.primary.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(PressScale()).focusEffectDisabled()
            .animation(.spring(duration: 0.25), value: recording)
            if combo != nil {
                Button { prefs.hotkeys[action.rawValue] = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).focusEffectDisabled().help("Remove shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            if e.keyCode == 51 { prefs.hotkeys[action.rawValue] = nil; stop(); return nil }
            if let c = HotkeyCombo(event: e) { prefs.hotkeys[action.rawValue] = c; stop() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
