// A harmless menu bar app used to test that Guard can really close and restart an app.
import AppKit
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: 24); item.button?.title = "D"
app.run()
