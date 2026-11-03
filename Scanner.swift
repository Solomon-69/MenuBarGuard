// Scanner.swift: reads the real menu bar. macOS 26+ no longer lists menu bar icons as windows,
// so each running app is asked (through Accessibility) where its menu bar icons are.
import AppKit
import ApplicationServices

enum Scanner {
    static func trusted(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Where the free icon area begins and ends, on the screen that has the notch (or the main one).
    @MainActor static func geometry() -> (rightMin: CGFloat, maxX: CGFloat) {
        let screen = NSScreen.screens.first { $0.auxiliaryTopRightArea != nil } ?? NSScreen.screens.first
        guard let s = screen else { return (0, 0) }
        let min = s.auxiliaryTopRightArea?.minX ?? (s.frame.minX + s.frame.width * 0.42)
        return (min, s.frame.maxX)
    }

    /// Menu bar icons per app. Runs off the main thread (a stuck app must not freeze the panel).
    static func scanItems(selfPID: Int32) -> [BarItem] {
        var out: [BarItem] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != selfPID {
            guard let id = app.bundleIdentifier else { continue }
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.25)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, "AXExtrasMenuBar" as CFString, &bar) == .success, let b = bar else { continue }
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(b as! AXUIElement, kAXChildrenAttribute as CFString, &kids)
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            for c in (kids as? [AXUIElement]) ?? [] {
                var p: CFTypeRef?, s: CFTypeRef?
                AXUIElementCopyAttributeValue(c, kAXPositionAttribute as CFString, &p)
                AXUIElementCopyAttributeValue(c, kAXSizeAttribute as CFString, &s)
                var pt = CGPoint.zero, sz = CGSize.zero
                if let p = p { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
                if let s = s { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
                lo = min(lo, pt.x); hi = max(hi, pt.x + sz.width)
            }
            if hi > lo {
                out.append(BarItem(pid: app.processIdentifier, bundleID: id,
                                   name: app.localizedName ?? id, x: lo, width: hi - lo))
            }
        }
        return out
    }
}
