// make-icon.swift: draws assets/Roomy.icns. Run: swift make-icon.swift
import AppKit
let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let r = NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88)
    let body = NSBezierPath(roundedRect: r, xRadius: s*0.2, yRadius: s*0.2)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.17, blue: 0.19, alpha: 1), NSColor(red: 0.05, green: 0.08, blue: 0.10, alpha: 1)])!.draw(in: body, angle: -90)
    // the menu bar strip with a notch and little icons
    let bar = NSRect(x: r.minX, y: r.maxY - s*0.17, width: r.width, height: s*0.17)
    NSGraphicsContext.saveGraphicsState(); body.addClip()
    NSColor(white: 1, alpha: 0.10).setFill(); bar.fill()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.36, y: bar.minY, width: s*0.2, height: bar.height*0.62), xRadius: s*0.03, yRadius: s*0.03).fill()
    for i in 0..<4 {
        NSColor(red: 0.30, green: 0.86, blue: 0.76, alpha: i == 0 ? 0.35 : 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: s*(0.62 + 0.07*CGFloat(i)), y: bar.midY - s*0.022, width: s*0.044, height: s*0.044)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    // shield
    if let sym = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s*0.46, weight: .semibold)) {
        let t = NSImage(size: sym.size); t.lockFocus()
        sym.draw(in: NSRect(origin: .zero, size: sym.size)); NSColor(red: 0.30, green: 0.86, blue: 0.76, alpha: 1).setFill()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop); t.unlockFocus()
        t.draw(in: NSRect(x: (s - sym.size.width)/2, y: s*0.14, width: sym.size.width, height: sym.size.height))
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
let set = dir.appendingPathComponent("assets/Roomy.iconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (n, px) in [("16",16),("16@2x",32),("32",32),("32@2x",64),("128",128),("128@2x",256),("256",256),("256@2x",512),("512",512),("512@2x",1024)] {
    try! render(px).write(to: set.appendingPathComponent("icon_\(n.replacingOccurrences(of: "@2x", with: "")==n ? n+"x"+n : n.replacingOccurrences(of: "@2x", with: "x")+"@2x").png"))
}
let p = Process(); p.launchPath = "/usr/bin/iconutil"; p.arguments = ["-c", "icns", set.path, "-o", dir.appendingPathComponent("assets/Roomy.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
