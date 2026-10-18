// Draws the app icon (design A, "Bridge"): white car crossing a bridge arch on a sunset gradient.
// Usage: swift icon.swift OUT.png SIZE
import AppKit

let out = CommandLine.arguments[1], n = CGFloat(Double(CommandLine.arguments[2])!)
let img = NSImage(size: NSSize(width: n, height: n))
img.lockFocus()

// macOS icon grid: the shape fills ~80% of the canvas.
let r = NSRect(x: 0, y: 0, width: n, height: n).insetBy(dx: n * 0.1, dy: n * 0.1)
let s = r.width / 432  // the design was drawn on a 432 pt tile
let shape = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
NSGradient(colors: [NSColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1),
                    NSColor(red: 0.93, green: 0.22, blue: 0.45, alpha: 1),
                    NSColor(red: 0.45, green: 0.18, blue: 0.75, alpha: 1)])!.draw(in: shape, angle: -60)

NSColor.white.withAlphaComponent(0.9).setStroke()
let arch = NSBezierPath()
arch.lineWidth = 22 * s
arch.lineCapStyle = .round
arch.move(to: NSPoint(x: r.minX + 60 * s, y: r.minY + 120 * s))
arch.curve(to: NSPoint(x: r.maxX - 60 * s, y: r.minY + 120 * s),
           controlPoint1: NSPoint(x: r.minX + 140 * s, y: r.minY + 300 * s),
           controlPoint2: NSPoint(x: r.maxX - 140 * s, y: r.minY + 300 * s))
arch.stroke()
let deck = NSBezierPath()
deck.lineWidth = 14 * s
deck.lineCapStyle = .round
deck.move(to: NSPoint(x: r.minX + 40 * s, y: r.minY + 120 * s))
deck.line(to: NSPoint(x: r.maxX - 40 * s, y: r.minY + 120 * s))
deck.stroke()

let cfg = NSImage.SymbolConfiguration(pointSize: 120 * s, weight: .semibold).applying(.init(paletteColors: [.white]))
let car = NSImage(systemSymbolName: "car.side.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
car.draw(in: NSRect(x: r.midX - car.size.width / 2, y: r.midY - car.size.height / 2 + 70 * s,
                    width: car.size.width, height: car.size.height))
img.unlockFocus()

// Write exactly n x n pixels (lockFocus renders at the screen's scale).
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(n), pixelsHigh: Int(n), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
