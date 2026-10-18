// Draws the app icon: white car symbol on a blue rounded square. Usage: swift icon.swift OUT.png SIZE
import AppKit
let out = CommandLine.arguments[1], n = CGFloat(Double(CommandLine.arguments[2])!)
let img = NSImage(size: NSSize(width: n, height: n))
img.lockFocus()
let inset = n * 0.1, r = NSRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)
let path = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
NSGradient(starting: NSColor(red: 0.16, green: 0.45, blue: 0.98, alpha: 1),
           ending: NSColor(red: 0.05, green: 0.20, blue: 0.62, alpha: 1))!.draw(in: path, angle: -90)
let cfg = NSImage.SymbolConfiguration(pointSize: n * 0.36, weight: .semibold).applying(.init(paletteColors: [.white]))
let car = NSImage(systemSymbolName: "car.side.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
car.draw(in: NSRect(x: (n - car.size.width) / 2, y: (n - car.size.height) / 2 + n * 0.02, width: car.size.width, height: car.size.height))
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
