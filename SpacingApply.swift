// SpacingApply.swift: writes the menu bar icon gap (a system setting) and can relaunch menu bar apps
// so they pick it up. Apps only read the setting when they start.
import AppKit

enum SpacingApply {
    private static let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]

    /// Writes (or, for 0, removes) the setting for this Mac user.
    static func write(offset: Int) {
        let v = Spacing.values(offset: offset)
        let vals: [Int?] = [v?.spacing, v?.padding]
        for (k, val) in zip(keys, vals) {
            CFPreferencesSetValue(k as CFString, val.map { $0 as CFNumber }, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// What is saved now (nil = system default).
    static func read() -> (spacing: Int?, padding: Int?) {
        func r(_ k: String) -> Int? {
            CFPreferencesCopyValue(k as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
        }
        return (r(keys[0]), r(keys[1]))
    }

    /// Third-party menu bar apps that can be relaunched: not Apple's, not ours, not locked in the priority list.
    @MainActor static func relaunchable(_ entries: [BarEntry], locked: Set<String>) -> [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>(), out: [NSRunningApplication] = []
        for e in entries where !e.bundleID.hasPrefix("com.apple.") && e.bundleID != own && !locked.contains(e.bundleID) {
            guard seen.insert(e.bundleID).inserted, let app = NSRunningApplication(processIdentifier: e.pid), app.bundleURL != nil else { continue }
            out.append(app)
        }
        return out
    }

    /// Politely quits each app, then opens it again in the background.
    @MainActor static func relaunch(_ apps: [NSRunningApplication], log: @escaping (String) -> Void) {
        Task { @MainActor in
            for app in apps {
                guard let url = app.bundleURL else { continue }
                let name = app.localizedName ?? url.lastPathComponent
                app.terminate()
                var waited = 0.0
                while !app.isTerminated, waited < 6 { try? await Task.sleep(nanoseconds: 200_000_000); waited += 0.2 }
                guard app.isTerminated else { log("\(name) did not quit, so it keeps the old spacing."); continue }
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.addsToRecentItems = false
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
                log("Relaunched \(name) for the new icon spacing.")
            }
        }
    }
}
