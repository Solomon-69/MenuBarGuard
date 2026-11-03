// Liquid-glass versions of the deep teal icon (C2): smaller glass shield on a teal squircle.
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
func masked(_ name: String, _ pt: CGFloat, _ w: NSFont.Weight, _ paint: (NSRect) -> Void) -> NSImage {
    let s = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: pt, weight: w))!
    let t = NSImage(size: s.size); t.lockFocus()
    paint(NSRect(origin: .zero, size: s.size))
    s.draw(in: NSRect(origin: .zero, size: s.size), from: .zero, operation: .destinationIn, fraction: 1); t.unlockFocus(); return t
}
struct G { var name: String; var bg: [NSColor]; var blobA: NSColor; var blobB: NSColor; var glass: CGFloat; var tint: NSColor }
func render(_ g: G, _ S: CGFloat = 1024) -> NSImage {
    let img = NSImage(size: NSSize(width: S, height: S)); img.lockFocus()
    let r = NSRect(x: S*0.06, y: S*0.06, width: S*0.88, height: S*0.88)
    let body = NSBezierPath(roundedRect: r, xRadius: S*0.2, yRadius: S*0.2)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.35); sh.shadowBlurRadius = S*0.03; sh.shadowOffset = NSSize(width: 0, height: -S*0.014); sh.set()
    NSGradient(colors: g.bg)!.draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); body.addClip()
    // colour blobs the glass bends
    NSGradient(colors: [g.blobA, g.blobA.withAlphaComponent(0)])!.draw(fromCenter: NSPoint(x: S*0.30, y: S*0.30), radius: 0, toCenter: NSPoint(x: S*0.30, y: S*0.30), radius: S*0.42, options: [])
    NSGradient(colors: [g.blobB, g.blobB.withAlphaComponent(0)])!.draw(fromCenter: NSPoint(x: S*0.74, y: S*0.72), radius: 0, toCenter: NSPoint(x: S*0.74, y: S*0.72), radius: S*0.40, options: [])
    NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!.draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height/2), angle: -90)
    let P = S*0.62
    let probe = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: P, weight: .regular))!
    let ox = (S - probe.size.width)/2, oy = (S - probe.size.height)/2
    func at(_ i: NSImage, _ op: NSCompositingOperation = .sourceOver) { i.draw(in: NSRect(x: ox + (probe.size.width - i.size.width)/2, y: oy + (probe.size.height - i.size.height)/2, width: i.size.width, height: i.size.height), from: .zero, operation: op, fraction: 1) }
    // soft shadow around the glass, cut out of the middle so the glass stays clear
    let shadowLayer = NSImage(size: NSSize(width: S, height: S)); shadowLayer.lockFocus()
    NSGraphicsContext.saveGraphicsState()
    let ds = NSShadow(); ds.shadowColor = c(0, 0.08, 0.10, 0.55); ds.shadowBlurRadius = S*0.05; ds.shadowOffset = NSSize(width: 0, height: -S*0.025); ds.set()
    at(masked("shield.fill", P, .regular) { NSColor.black.setFill(); $0.fill() })
    NSGraphicsContext.restoreGraphicsState()
    at(masked("shield.fill", P, .regular) { NSColor.black.setFill(); $0.fill() }, .destinationOut)
    shadowLayer.unlockFocus()
    shadowLayer.draw(in: NSRect(x: 0, y: 0, width: S, height: S))
    // glass body: clear at the bottom, milky at the top, tinted
    at(masked("shield.fill", P, .regular) { rect in
        NSGradient(colors: [NSColor(white: 1, alpha: g.glass), g.tint.withAlphaComponent(g.glass*0.45), NSColor(white: 1, alpha: g.glass*0.55)])!.draw(in: rect, angle: -90)
        NSGradient(colors: [NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0)])!.draw(fromCenter: NSPoint(x: rect.minX + rect.width*0.30, y: rect.maxY - rect.height*0.16), radius: 0, toCenter: NSPoint(x: rect.minX + rect.width*0.30, y: rect.maxY - rect.height*0.16), radius: rect.width*0.55, options: [])
    })
    // bright edge (light catches the top, fades to the bottom)
    at(masked("shield", P, .regular) { rect in
        NSGradient(colors: [NSColor(white: 1, alpha: 0.98), NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0.30)])!.draw(in: rect, angle: -90)
    })
    // glyph
    let gl = masked("menubar.rectangle", S*0.20, .semibold) { NSColor(white: 1, alpha: 0.95).setFill(); $0.fill() }
    NSGraphicsContext.saveGraphicsState()
    let gs = NSShadow(); gs.shadowColor = c(0, 0.15, 0.18, 0.35); gs.shadowBlurRadius = S*0.012; gs.shadowOffset = NSSize(width: 0, height: -S*0.006); gs.set()
    gl.draw(in: NSRect(x: (S - gl.size.width)/2, y: oy + probe.size.height*0.50 - gl.size.height/2, width: gl.size.width, height: gl.size.height))
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 1, alpha: 0.35).setStroke(); body.lineWidth = S*0.004; body.stroke()
    img.unlockFocus(); return img
}
let teal = [c(0.12,0.56,0.55), c(0.03,0.22,0.27)]
let gs = [
 G(name: "G1  Deep teal glass", bg: teal, blobA: c(0.35,0.95,0.85,0.55), blobB: c(0.20,0.45,0.85,0.45), glass: 0.30, tint: c(0.6,1,0.95)),
 G(name: "G2  Aqua glow", bg: [c(0.10,0.62,0.62), c(0.02,0.25,0.32)], blobA: c(0.55,1,0.9,0.7), blobB: c(0.45,0.35,0.95,0.5), glass: 0.26, tint: c(0.7,1,1)),
 G(name: "G3  Frosted", bg: teal, blobA: c(0.35,0.95,0.85,0.35), blobB: c(0.20,0.45,0.85,0.30), glass: 0.50, tint: c(0.85,1,0.98)),
 G(name: "G4  Dark glass", bg: [c(0.06,0.34,0.36), c(0.01,0.10,0.14)], blobA: c(0.25,0.85,0.78,0.5), blobB: c(0.15,0.40,0.75,0.45), glass: 0.20, tint: c(0.5,0.95,0.9)),
]
let S: CGFloat = 400
let sheet = NSImage(size: NSSize(width: 4*(S+30)+30, height: S+100)); sheet.lockFocus()
NSColor(white: 0.12, alpha: 1).setFill(); NSRect(origin: .zero, size: sheet.size).fill()
for (i, g) in gs.enumerated() {
    let img = render(g); let x = 30 + CGFloat(i)*(S+30)
    img.draw(in: NSRect(x: x, y: 70, width: S, height: S))
    (g.name as NSString).draw(at: NSPoint(x: x + 8, y: 22), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.white])
    try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("glass-\(g.name.prefix(2)).png"))
}
sheet.unlockFocus()
try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("glass-options.png"))
