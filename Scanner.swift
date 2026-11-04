// Scanner.swift: reads the real menu bar. macOS 26+ no longer lists menu bar icons as windows,
// so each running app is asked (through Accessibility) where its menu bar icons are.
import AppKit
import ApplicationServices

enum Scanner {
    /// True when the last scan saw macOS's own « overflow arrow (icons pushed out of the bar).
    nonisolated(unsafe) static var sawOverflow = false
    nonisolated(unsafe) static var overflowFrame: CGRect = .zero
    static func trusted(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Asks for Accessibility the way that always works: clears a stale entry left by an older signature
    /// (macOS then shows the switch as on but ignores it), asks again, and opens the right Settings page.
    static func askAccessibility() {
        if !AXIsProcessTrusted(), let id = Bundle.main.bundleIdentifier {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", "Accessibility", id]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        _ = trusted(prompt: true)
        if !AXIsProcessTrusted(), let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSWorkspace.shared.open(u) }
        }
    }

    /// Where the free icon area begins and ends, on the screen that has the notch (or the main one).
    @MainActor static func geometry() -> (rightMin: CGFloat, maxX: CGFloat) {
        let screen = NSScreen.screens.first { $0.auxiliaryTopRightArea != nil } ?? NSScreen.screens.first
        guard let s = screen else { return (0, 0) }
        let min = s.auxiliaryTopRightArea?.minX ?? (s.frame.minX + s.frame.width * 0.42)
        return (min, s.frame.maxX)
    }

    /// Menu bar icons per app (one span per app). Kept for the live scan test.
    static func scanItems(selfPID: Int32) -> [BarItem] {
        var spans: [String: BarItem] = [:]
        for e in scanEntries(selfPID: selfPID) {
            if var s = spans[e.bundleID] {
                let hi = max(s.x + s.width, e.x + e.width); s.x = min(s.x, e.x); s.width = hi - s.x; spans[e.bundleID] = s
            } else {
                spans[e.bundleID] = BarItem(pid: e.pid, bundleID: e.bundleID, name: e.appName, x: e.x, width: e.width)
            }
        }
        return Array(spans.values)
    }

    /// Every menu bar icon of every app. Runs off the main thread (a stuck app must not freeze the panel).
    static func scanEntries(selfPID: Int32) -> [BarEntry] {
        var out: [BarEntry] = []
        var overflow = false, ovFrame = CGRect.zero
        defer { sawOverflow = overflow; overflowFrame = ovFrame }
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != selfPID {
            guard let id = app.bundleIdentifier else { continue }
            let system = id == "com.apple.MenuBarAgent" || id == "com.apple.controlcenter" || id == "com.apple.systemuiserver"
            for (i, c) in extras(app.processIdentifier).enumerated() {
                let f = frame(c)
                guard f.width > 0 else { continue }
                var ident: CFTypeRef?
                AXUIElementCopyAttributeValue(c, kAXIdentifierAttribute as CFString, &ident)
                if (ident as? String)?.contains("overflow-indicator") == true {
                    // Only counts when it is really on screen (macOS keeps it around off screen when not needed).
                    let onScreen = NSScreen.screens.contains { f.minX >= $0.frame.minX && f.maxX <= $0.frame.maxX } && f.minX > 1 && f.height > 4
                    if onScreen { overflow = true }
                    ovFrame = f; continue
                }     // macOS's own "more" chevron
                let label = text(c)
                out.append(BarEntry(pid: app.processIdentifier, bundleID: id, appName: system ? "Apple" : (app.localizedName ?? id), index: i,
                                    x: f.minX, y: f.minY, width: f.width, height: f.height,
                                    label: system && label.isEmpty ? "system icon \(i + 1)" : label))
            }
        }
        return out.sorted { $0.x < $1.x }
    }

    /// The accessibility elements of one app's menu bar icons.
    static func extras(_ pid: Int32) -> [AXUIElement] {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.25)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXExtrasMenuBar" as CFString, &bar) == .success, let b = bar,
              CFGetTypeID(b) == AXUIElementGetTypeID() else { return [] }
        var kids: CFTypeRef?
        AXUIElementCopyAttributeValue(b as! AXUIElement, kAXChildrenAttribute as CFString, &kids)
        return (kids as? [AXUIElement]) ?? []
    }

    static func frame(_ c: AXUIElement) -> CGRect {
        var p: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(c, kAXPositionAttribute as CFString, &p)
        AXUIElementCopyAttributeValue(c, kAXSizeAttribute as CFString, &s)
        var pt = CGPoint.zero, sz = CGSize.zero
        if let p, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
        if let s, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
        return CGRect(origin: pt, size: sz)
    }

    private static func text(_ c: AXUIElement) -> String {
        for key in [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(c, key as CFString, &v) == .success, let s = v as? String, !s.isEmpty { return s }
        }
        return ""
    }

    /// Opens one icon's menu, the same as clicking it. Returns false if the app refused.
    static func press(pid: Int32, index: Int) -> Bool {
        let all = extras(pid)
        guard all.indices.contains(index) else { return false }
        return AXUIElementPerformAction(all[index], kAXPressAction as CFString) == .success
    }

    /// The right edge of the front app's menus (File, Edit, ...), to tell empty menu bar space from menus.
    static func appMenusMaxX() -> CGFloat {
        guard let app = NSWorkspace.shared.frontmostApplication else { return 0 }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.2)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &bar) == .success, let b = bar,
              CFGetTypeID(b) == AXUIElementGetTypeID() else { return 0 }
        var kids: CFTypeRef?
        AXUIElementCopyAttributeValue(b as! AXUIElement, kAXChildrenAttribute as CFString, &kids)
        return ((kids as? [AXUIElement]) ?? []).map { frame($0).maxX }.max() ?? 0
    }
}
