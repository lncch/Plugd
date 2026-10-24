import SwiftUI

/// The menu bar menu: adapter status and the main actions, without opening the window.
struct MenuBarMenu: View {
    @EnvironmentObject var engine: Engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if engine.plugdUpdateAvailable, let latest = engine.plugdLatest {
            Button("Download Plugd \(latest)…") { NSWorkspace.shared.open(Engine.plugdDownload) }
            Divider()
        }
        if engine.ready {
            Text(status)
            if let volts = engine.adapter?.volts { Text("Car battery \(volts)") }
            Divider()
            if engine.running {
                Button("Quit FORScan") { Task { await engine.quitForscan() } }.disabled(engine.busy)
            } else {
                Button(engine.busy ? "Starting FORScan…" : "Open FORScan") { Task { await engine.openForscan() } }
                    .disabled(engine.busy || engine.serialBusy)
            }
            Button(engine.codes == .checking ? "Checking Engine Codes…" : "Check Engine Codes") { Task { await engine.checkCodes() } }
                .disabled(!engine.canUseAdapter)
            if let codes { Text(codes) }
            Divider()
        }
        Button("Open Plugd") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Plugd") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private var status: String {
        guard engine.port != nil else { return "No adapter plugged in" }
        if engine.running { return "FORScan is open" }
        if engine.bluetoothWaiting { return "Bluetooth adapter paired" }
        return "\(engine.adapter?.version ?? "Adapter") connected"
    }

    private var codes: String? {
        switch engine.codes {
        case .ok(let s, let p): s.isEmpty && p.isEmpty ? "No engine codes" : "Codes: " + (s + p.filter { !s.contains($0) }).joined(separator: ", ")
        case .failed(let m): m
        default: nil
        }
    }

    /// The OBD port from the logo, simplified to 2 rows of 5 pins so it reads at menu bar size.
    static let icon: NSImage = {
        let img = NSImage(size: NSSize(width: 22, height: 14), flipped: true) { _ in
            let port = NSBezierPath()
            port.move(to: NSPoint(x: 1.5, y: 1.5))
            port.line(to: NSPoint(x: 20.5, y: 1.5))
            port.line(to: NSPoint(x: 17.5, y: 12.5))
            port.line(to: NSPoint(x: 4.5, y: 12.5))
            port.close()
            for (row, y, x0) in [(0, 3.6, 5.2), (1, 8.1, 6.2)] {
                for i in 0..<5 {
                    let w = row == 0 ? 2.6 : 2.15
                    port.append(NSBezierPath(roundedRect: NSRect(x: x0 + Double(i) * w, y: y, width: 1.1, height: 2.4), xRadius: 0.55, yRadius: 0.55))
                }
            }
            port.windingRule = .evenOdd
            port.lineJoinStyle = .round
            NSColor.black.setFill()
            port.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
