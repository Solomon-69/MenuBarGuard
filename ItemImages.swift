// ItemImages.swift: pictures of the real menu bar icons, for the Ice Bar, search and Settings.
// Needs Screen Recording permission (asked once). Icons can only be photographed while they are on
// screen, so pictures are taken whenever a hidden section is shown and kept until the next time.
// Without permission, the app's own icon and name are shown instead.
import AppKit
import ScreenCaptureKit

@MainActor final class ItemImages: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var allowed = CGPreflightScreenCaptureAccess()
    private var busy = false
    private(set) var lastCapture = Date.distantPast

    func recheck() { allowed = CGPreflightScreenCaptureAccess() }

    /// Asks once (macOS shows its own prompt the first time, later it only opens System Settings).
    func request() {
        UserDefaults.standard.set(true, forKey: "askedScreenRecording")
        allowed = CGRequestScreenCaptureAccess()
        if !allowed, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
    }

    var asked: Bool { UserDefaults.standard.bool(forKey: "askedScreenRecording") }

    func image(_ e: BarEntry) -> NSImage? { images[e.id] }

    /// Photographs the icons that are on screen now (one capture of the menu bar, then cut up).
    func capture(_ entries: [BarEntry]) async {
        recheck()
        guard allowed, !busy, let screen = MenuBarGeometry.screen else { return }
        busy = true; defer { busy = false }
        let top = screen.frame.maxY
        let barH = MenuBarGeometry.height(screen)
        // Top-left based rect of the menu bar on this screen.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? top
        let strip = CGRect(x: screen.frame.minX, y: primaryTop - top, width: screen.frame.width, height: barH)
        let notch: ClosedRange<CGFloat>? = {
            guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return nil }
            return l.maxX...r.minX
        }()
        guard let cg = await Self.grab(strip) else { return }
        let scale = CGFloat(cg.width) / strip.width
        var out = images
        for e in entries where e.x >= strip.minX && e.x + e.width <= strip.maxX && e.width > 2 {
            if let n = notch, n.overlaps(e.x...(e.x + e.width)) { continue }      // behind the notch: nothing to see
            let r = CGRect(x: (e.x - strip.minX) * scale, y: 0, width: e.width * scale, height: CGFloat(cg.height))
            if let c = cg.cropping(to: r.integral) {
                out[e.id] = NSImage(cgImage: c, size: NSSize(width: e.width, height: barH))
            }
        }
        images = out
        lastCapture = Date()
    }

    private static func grab(_ rect: CGRect) async -> CGImage? {
        if #available(macOS 15.2, *) {
            return try? await SCScreenshotManager.captureImage(in: rect)
        }
        return nil
    }
}
