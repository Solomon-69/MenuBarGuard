// Draws the app icon options into assets/icon-options (PNG + one contact sheet).
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let teal = NSColor(red: 0.30, green: 0.86, blue: 0.76, alpha: 1)
func sym(_ name: String, _ pt: CGFloat, _ color: NSColor, _ w: NSFont.Weight = .semibold) -> NSImage? {
    guard let s = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: pt, weight: w)) else { return nil }
    let t = NSImage(size: s.size); t.lockFocus(); s.draw(in: NSRect(origin: .zero, size: s.size)); color.setFill()
    NSRect(origin: .zero, size: s.size).fill(using: .sourceAtop); t.unlockFocus(); return t
}
func drawSym(_ n: String, _ pt: CGFloat, _ c: NSColor, centerX: CGFloat, centerY: CGFloat) {
    if let i = sym(n, pt, c) { i.draw(in: NSRect(x: centerX - i.size.width/2, y: centerY - i.size.height/2, width: i.size.width, height: i.size.height)) }
}
func canvas(_ s: CGFloat, _ bg: [NSColor], _ body: (CGFloat, NSRect) -> Void) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s)); img.lockFocus()
    let r = NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88)
    let p = NSBezierPath(roundedRect: r, xRadius: s*0.2, yRadius: s*0.2)
    NSGradient(colors: bg)!.draw(in: p, angle: -90)
    NSGraphicsContext.saveGraphicsState(); p.addClip(); body(s, r); NSGraphicsContext.restoreGraphicsState()
    img.unlockFocus(); return img
}
func strip(_ s: CGFloat, _ r: NSRect, dim: Bool = true) {
    let bar = NSRect(x: r.minX, y: r.maxY - s*0.17, width: r.width, height: s*0.17)
    NSColor(white: 1, alpha: 0.10).setFill(); bar.fill(); NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.36, y: bar.minY, width: s*0.2, height: bar.height*0.62), xRadius: s*0.03, yRadius: s*0.03).fill()
    for i in 0..<4 { teal.withAlphaComponent(i == 0 && dim ? 0.35 : 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: s*(0.62 + 0.07*CGFloat(i)), y: bar.midY - s*0.022, width: s*0.044, height: s*0.044)).fill() }
}
let dark = [NSColor(red: 0.10, green: 0.17, blue: 0.19, alpha: 1), NSColor(red: 0.05, green: 0.08, blue: 0.10, alpha: 1)]
let S: CGFloat = 512
let options: [(String, NSImage)] = [
 ("A  Shield + notch", canvas(S, dark) { s, r in strip(s, r); drawSym("shield.lefthalf.filled", s*0.46, teal, centerX: s/2, centerY: s*0.42) }),
 ("B  All icons visible", canvas(S, [NSColor(red: 0.16, green: 0.66, blue: 0.60, alpha: 1), NSColor(red: 0.08, green: 0.38, blue: 0.42, alpha: 1)]) { s, r in
    let bar = NSRect(x: r.minX, y: r.midY - s*0.10, width: r.width, height: s*0.20); NSColor(white: 1, alpha: 0.16).setFill(); bar.fill()
    NSColor(white: 0.04, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: s*0.14, y: bar.minY - s*0.02, width: s*0.2, height: bar.height + s*0.02), xRadius: s*0.04, yRadius: s*0.04).fill()
    for i in 0..<6 { NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: s*(0.42 + 0.075*CGFloat(i)), y: bar.midY - s*0.03, width: s*0.052, height: s*0.06), xRadius: s*0.014, yRadius: s*0.014).fill() }
    drawSym("checkmark.circle.fill", s*0.18, .white, centerX: s/2, centerY: s*0.27) }),
 ("C  Light shield", canvas(S, [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.86, alpha: 1)]) { s, r in
    drawSym("shield.fill", s*0.56, NSColor(red: 0.13, green: 0.60, blue: 0.55, alpha: 1), centerX: s/2, centerY: s*0.5)
    drawSym("menubar.rectangle", s*0.22, .white, centerX: s/2, centerY: s*0.5) }),
 ("D  Overflow arrow stopped", canvas(S, dark) { s, r in strip(s, r, dim: false)
    drawSym("chevron.left.2", s*0.34, teal.withAlphaComponent(0.45), centerX: s/2, centerY: s*0.42)
    drawSym("nosign", s*0.52, teal, centerX: s/2, centerY: s*0.42) }),
 ("E  Indigo glow", canvas(S, [NSColor(red: 0.36, green: 0.30, blue: 0.85, alpha: 1), NSColor(red: 0.10, green: 0.55, blue: 0.62, alpha: 1)]) { s, r in
    strip(s, r, dim: false); NSColor(white: 1, alpha: 0.9).setFill()
    drawSym("shield.checkered", s*0.46, .white, centerX: s/2, centerY: s*0.42) }),
]
let W: CGFloat = 5*(S+30)+30, H = S + 100
let sheet = NSImage(size: NSSize(width: W, height: H)); sheet.lockFocus()
NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, o) in options.enumerated() {
    let x = 30 + CGFloat(i)*(S+30)
    o.1.draw(in: NSRect(x: x, y: 70, width: S, height: S))
    (o.0 as NSString).draw(at: NSPoint(x: x + 10, y: 22), withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.white])
    let rep = NSBitmapImageRep(data: o.1.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("option-\(o.0.prefix(1)).png"))
}
sheet.unlockFocus()
try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon-options.png"))
