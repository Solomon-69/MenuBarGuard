// Premium versions of the "light shield" icon (option C): bigger centred shield, depth, gloss.
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
func shieldImage(_ pt: CGFloat, _ g: NSGradient) -> NSImage {
    let s = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: pt, weight: .regular))!
    let t = NSImage(size: s.size); t.lockFocus()
    s.draw(in: NSRect(origin: .zero, size: s.size)); NSGraphicsContext.current!.compositingOperation = .sourceAtop
    g.draw(in: NSRect(origin: .zero, size: s.size), angle: -90); t.unlockFocus(); return t
}
func glyph(_ name: String, _ pt: CGFloat, _ color: NSColor) -> NSImage {
    let s = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: pt, weight: .semibold))!
    let t = NSImage(size: s.size); t.lockFocus(); s.draw(in: NSRect(origin: .zero, size: s.size)); color.setFill()
    NSRect(origin: .zero, size: s.size).fill(using: .sourceAtop); t.unlockFocus(); return t
}
struct Style { var name: String; var bg: [NSColor]; var shield: [NSColor]; var glyph: NSColor; var rim: NSColor; var shadow: NSColor; var gloss: CGFloat }
func render(_ st: Style, _ S: CGFloat = 1024) -> NSImage {
    let img = NSImage(size: NSSize(width: S, height: S)); img.lockFocus()
    let r = NSRect(x: S*0.06, y: S*0.06, width: S*0.88, height: S*0.88)
    let body = NSBezierPath(roundedRect: r, xRadius: S*0.2, yRadius: S*0.2)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.35); sh.shadowBlurRadius = S*0.03; sh.shadowOffset = NSSize(width: 0, height: -S*0.014); sh.set()
    NSGradient(colors: st.bg)!.draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); body.addClip()
    // soft light from the top
    NSGradient(colors: [NSColor(white: 1, alpha: st.gloss), NSColor(white: 1, alpha: 0)])!.draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height/2), angle: -90)
    // big shield, centred, with depth
    let g = NSGradient(colors: st.shield)!
    let shield = shieldImage(S*0.78, g)
    let sx = (S - shield.size.width)/2, sy = (S - shield.size.height)/2 - S*0.005
    NSGraphicsContext.saveGraphicsState()
    let ds = NSShadow(); ds.shadowColor = st.shadow; ds.shadowBlurRadius = S*0.035; ds.shadowOffset = NSSize(width: 0, height: -S*0.018); ds.set()
    shield.draw(in: NSRect(x: sx, y: sy, width: shield.size.width, height: shield.size.height))
    NSGraphicsContext.restoreGraphicsState()
    // menu bar glyph in the middle of the shield
    let m = glyph("menubar.rectangle", S*0.27, st.glyph)
    m.draw(in: NSRect(x: (S - m.size.width)/2, y: sy + shield.size.height*0.50 - m.size.height/2, width: m.size.width, height: m.size.height))
    NSGraphicsContext.restoreGraphicsState()
    // glass rim
    st.rim.withAlphaComponent(0.45).setStroke(); body.lineWidth = S*0.004; body.stroke()
    img.unlockFocus(); return img
}
let styles = [
 Style(name: "C1  Pearl", bg: [c(0.99,0.99,1), c(0.83,0.87,0.88)], shield: [c(0.26,0.80,0.72), c(0.07,0.45,0.46)], glyph: c(1,1,1,0.95), rim: .white, shadow: c(0.02,0.25,0.28,0.45), gloss: 0.5),
 Style(name: "C2  Deep teal", bg: [c(0.12,0.56,0.55), c(0.03,0.22,0.27)], shield: [c(0.96,1,1), c(0.74,0.92,0.90)], glyph: c(0.07,0.42,0.43), rim: .white, shadow: c(0,0.1,0.12,0.5), gloss: 0.28),
 Style(name: "C3  Midnight glow", bg: [c(0.10,0.15,0.18), c(0.02,0.04,0.06)], shield: [c(0.42,0.95,0.84), c(0.10,0.58,0.56)], glyph: c(0.03,0.12,0.14,0.9), rim: c(0.5,1,0.9), shadow: c(0.2,0.9,0.8,0.40), gloss: 0.12),
 Style(name: "C4  Frosted mint", bg: [c(0.90,0.98,0.96), c(0.64,0.86,0.84)], shield: [c(1,1,1), c(0.86,0.96,0.94)], glyph: c(0.13,0.60,0.55), rim: .white, shadow: c(0.05,0.35,0.35,0.35), gloss: 0.6),
]
let S: CGFloat = 400
let sheet = NSImage(size: NSSize(width: 4*(S+30)+30, height: S+100)); sheet.lockFocus()
NSColor(white: 0.12, alpha: 1).setFill(); NSRect(origin: .zero, size: sheet.size).fill()
for (i, st) in styles.enumerated() {
    let img = render(st); let x = 30 + CGFloat(i)*(S+30)
    img.draw(in: NSRect(x: x, y: 70, width: S, height: S))
    (st.name as NSString).draw(at: NSPoint(x: x + 8, y: 22), withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white])
    try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("premium-\(st.name.prefix(2)).png"))
}
sheet.unlockFocus()
try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("premium-options.png"))
