// Draws the app icon ("Docked"): white car parked on a Dock-style shelf on a sunset gradient.
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

// Dock shelf with the "running" dot under it, like the macOS Dock.
let shelf = NSBezierPath(roundedRect: NSRect(x: r.minX + 50 * s, y: r.minY + 110 * s, width: r.width - 100 * s, height: 46 * s),
                         xRadius: 23 * s, yRadius: 23 * s)
NSColor.white.withAlphaComponent(0.28).setFill()
shelf.fill()
NSColor.white.withAlphaComponent(0.9).setStroke()
shelf.lineWidth = 6 * s
shelf.stroke()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: r.midX - 7 * s, y: r.minY + 80 * s, width: 14 * s, height: 14 * s)).fill()

let cfg = NSImage.SymbolConfiguration(pointSize: 128 * s, weight: .semibold).applying(.init(paletteColors: [.white]))
let car = NSImage(systemSymbolName: "car.side.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
car.draw(in: NSRect(x: r.midX - car.size.width / 2, y: r.minY + 150 * s, width: car.size.width, height: car.size.height))
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
