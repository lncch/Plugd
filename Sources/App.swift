import SwiftUI

@main
struct ScanBridgeApp: App {
    @StateObject private var engine = Engine()

    init() {
        // Test hook: run the whole setup with no window, print the log, exit.
        if CommandLine.arguments.contains("--headless-setup") {
            let e = Engine()
            e.autoAcceptEula = true
            Task { @MainActor in
                await e.setUp()
                print(e.log.joined(separator: "\n"))
                print("READY=\(e.ready) rosetta=\(e.rosetta) wine=\(e.wine) forscan=\(e.forscan)")
                exit(e.ready ? 0 : 1)
            }
            RunLoop.main.run()
        }
        // Test hook: press "Open FORScan" with no window, report what happened, leave FORScan open.
        if CommandLine.arguments.contains("--headless-open") {
            let e = Engine()
            Task { @MainActor in
                await e.openForscan()
                print(e.log.joined(separator: "\n"))
                print("RUNNING=\(e.running) COM1=\(e.mappedPort ?? "none")")
                exit(e.running ? 0 : 1)
            }
            RunLoop.main.run()
        }
    }

    var body: some Scene {
        Window("ScanBridge", id: "main") {
            ContentView()
                .environmentObject(engine)
                .frame(width: 480)
                .fixedSize(horizontal: false, vertical: true)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ScanBridge") { Self.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Link("ScanBridge on GitHub", destination: URL(string: "https://github.com/lncch/ScanBridge")!)
                Link("Report a Problem", destination: URL(string: "https://github.com/lncch/ScanBridge/issues")!)
                Divider()
                Link("FORScan Website", destination: URL(string: "https://forscan.org")!)
            }
        }
    }

    static func showAbout() {
        let text = """
        Runs FORScan on Apple Silicon Macs with Wine.
        Open source under the MIT license.
        github.com/lncch/ScanBridge

        FORScan is made by Alexey Savin (forscan.org).
        ScanBridge is not affiliated with FORScan, Ford or Mazda.
        Uses Wine (LGPL) and innoextract (zlib).
        """
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if engine.ready { MainPanel() } else { SetupPanel() }
            DisclosureGroup("Details", isExpanded: $showLog) {
                ScrollView {
                    Text(engine.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 90)
            }
            .font(.caption)
            Text("FORScan is made by Alexey Savin (forscan.org). ScanBridge is not affiliated with FORScan or Ford. It runs the Windows version of FORScan on your Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(isPresented: Binding(get: { engine.eulaText != nil }, set: { _ in })) {
            EulaSheet(text: engine.eulaText ?? "")
        }
        .alert(engine.notice ?? "", isPresented: Binding(get: { engine.notice != nil }, set: { if !$0 { engine.notice = nil } })) {
            Button("OK") { engine.notice = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("ScanBridge").font(.title2.bold())
                Text("FORScan on your Mac, no Windows needed").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Setup

struct SetupPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One-time setup").font(.headline)
            StepRow(title: "Rosetta", detail: "Apple's tool to run Intel apps", state: engine.rosetta)
            StepRow(title: "Wine", detail: "Runs Windows programs (≈190 MB download)", state: engine.wine)
            StepRow(title: "FORScan", detail: "Downloaded from forscan.org", state: engine.forscan)
            Button {
                Task { await engine.setUp() }
            } label: {
                Text(engine.busy ? "Setting up…" : "Set Up")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(engine.busy)
            .padding(.top, 4)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StepRow: View {
    let title: String
    let detail: String
    let state: StepState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(isFailed ? .red : .secondary)
            }
        }
    }

    private var isFailed: Bool { if case .failed = state { return true } else { return false } }

    private var subtitle: String {
        switch state {
        case .waiting, .done: return detail
        case .running(let s), .failed(let s): return s
        }
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// MARK: - Main

struct MainPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            adapterCard
            if engine.running {
                Button {
                    Task { await engine.quitForscan() }
                } label: {
                    Label("Quit FORScan", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(engine.busy)
            } else {
                Button {
                    Task { await engine.openForscan() }
                } label: {
                    Label(engine.busy ? "Opening…" : "Open FORScan", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(engine.busy)
            }
            HStack {
                Button("Add License Key…") { engine.importKey() }
                Spacer()
                Button("Show Files") { engine.revealFiles() }
            }
        }
    }

    private var adapterCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(engine.port == nil ? Color.secondary.opacity(0.5) : .green)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.port == nil ? "No OBD adapter" : "Adapter connected").fontWeight(.medium)
                Text(engine.port.map { "\($0) → COM1" } ?? "Plug in a USB OBD adapter (ELM327, OBDLink EX, vLinker FS)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if engine.running, let mapped = engine.mappedPort, mapped != engine.port {
                    Text("Adapter changed. Quit and reopen FORScan to use it.").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if engine.running {
                Text("FORScan running").font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EulaSheet: View {
    @EnvironmentObject var engine: Engine
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORScan License").font(.headline)
            Text("FORScan is free software by Alexey Savin. Read and accept its license to continue.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(text).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Decline") { engine.answerEula(false) }
                Button("I Accept") { engine.answerEula(true) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
