// Three icon concepts side by side. Usage: swift icons3.swift OUT.png
import AppKit
let n: CGFloat = 512, gap: CGFloat = 40
let canvas = NSImage(size: NSSize(width: n * 3 + gap * 4, height: n + gap * 2 + 60))
func squircle(_ r: NSRect) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225) }
func sym(_ name: String, _ size: CGFloat, _ colors: [NSColor], _ weight: NSFont.Weight = .semibold) -> NSImage {
    let c = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(c)!
}
func center(_ img: NSImage, in r: NSRect, dy: CGFloat = 0) {
    img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2 + dy, width: img.size.width, height: img.size.height))
}
func label(_ s: String, _ x: CGFloat) {
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.white]
    let t = NSAttributedString(string: s, attributes: a)
    t.draw(at: NSPoint(x: x + n / 2 - t.size().width / 2, y: 18))
}
canvas.lockFocus()
NSColor(white: 0.06, alpha: 1).setFill(); NSRect(origin: .zero, size: canvas.size).fill()
let y = gap + 60
// A: sunset gradient, white car crossing a bridge arch
var r = NSRect(x: gap, y: y, width: n, height: n).insetBy(dx: 40, dy: 40)
NSGradient(colors: [NSColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1), NSColor(red: 0.93, green: 0.22, blue: 0.45, alpha: 1), NSColor(red: 0.45, green: 0.18, blue: 0.75, alpha: 1)])!.draw(in: squircle(r), angle: -60)
let arch = NSBezierPath(); arch.lineWidth = 22; arch.lineCapStyle = .round
arch.move(to: NSPoint(x: r.minX + 60, y: r.minY + 120)); arch.curve(to: NSPoint(x: r.maxX - 60, y: r.minY + 120), controlPoint1: NSPoint(x: r.minX + 140, y: r.minY + 300), controlPoint2: NSPoint(x: r.maxX - 140, y: r.minY + 300))
NSColor.white.withAlphaComponent(0.9).setStroke(); arch.stroke()
let deck = NSBezierPath(); deck.lineWidth = 14; deck.lineCapStyle = .round; deck.move(to: NSPoint(x: r.minX + 40, y: r.minY + 120)); deck.line(to: NSPoint(x: r.maxX - 40, y: r.minY + 120)); deck.stroke()
center(sym("car.side.fill", 120, [.white]), in: r, dy: 70)
label("A  Bridge", gap)
// B: teal to blue, OBD plug with a spark
r = NSRect(x: gap * 2 + n, y: y, width: n, height: n).insetBy(dx: 40, dy: 40)
NSGradient(colors: [NSColor(red: 0.10, green: 0.85, blue: 0.75, alpha: 1), NSColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1)])!.draw(in: squircle(r), angle: -70)
let plug = NSBezierPath(); let pw: CGFloat = 250, ph: CGFloat = 150, px = r.midX - pw / 2, py = r.midY - ph / 2 - 10
plug.move(to: NSPoint(x: px, y: py + ph)); plug.line(to: NSPoint(x: px + pw, y: py + ph)); plug.line(to: NSPoint(x: px + pw - 30, y: py)); plug.line(to: NSPoint(x: px + 30, y: py)); plug.close()
NSColor.white.setFill(); plug.fill()
NSColor(red: 0.10, green: 0.50, blue: 0.90, alpha: 1).setFill()
for row in 0..<2 { for i in 0..<8 { let cx = px + 38 + CGFloat(i) * 25 + CGFloat(row) * 4, cy = py + ph - 45 - CGFloat(row) * 50; NSBezierPath(ovalIn: NSRect(x: cx, y: cy, width: 13, height: 13)).fill() } }
center(sym("bolt.fill", 90, [NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)]), in: r, dy: 130)
label("B  OBD plug", gap * 2 + n)
// C: deep blue to violet, car with signal waves
r = NSRect(x: gap * 3 + n * 2, y: y, width: n, height: n).insetBy(dx: 40, dy: 40)
NSGradient(colors: [NSColor(red: 0.12, green: 0.16, blue: 0.45, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.95, alpha: 1)])!.draw(in: squircle(r), angle: -90)
center(sym("car.side.fill", 150, [.white]), in: r, dy: -40)
center(sym("wave.3.right", 90, [NSColor(red: 0.35, green: 0.95, blue: 0.75, alpha: 1)], .bold), in: r, dy: 120)
label("C  Signal", gap * 3 + n * 2)
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
