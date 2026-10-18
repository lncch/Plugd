import SwiftUI

@main
struct OBDockApp: App {
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
        // Test hook: run the parser and redaction checks, exit 1 on any failure.
        if CommandLine.arguments.contains("--self-test") {
            var fails = DTC.selfTest() + Engine.redactSelfTest()
            if Engine.setupVersion("FORScanSetup2.3.71.release.exe") != "2.3.71" { fails.append("setupVersion") }
            if !Engine.older("2.3.9", "2.3.71") || Engine.older("2.3.71", "2.3.71") { fails.append("older") }
            print(fails.isEmpty ? "SELF-TEST OK" : fails.joined(separator: "\n"))
            exit(fails.isEmpty ? 0 : 1)
        }
        // Test hook: the same path as the window: auto-read the adapter at OBDOCK_PORT, then press Check.
        if CommandLine.arguments.contains("--headless-adapter") {
            let e = Engine()
            Task { @MainActor in
                for _ in 0..<50 where e.adapter == nil || e.serialBusy { try? await Task.sleep(nanoseconds: 200_000_000) }
                await e.checkCodes()
                print(e.log.joined(separator: "\n"))
                print("INFO=\(String(describing: e.adapter)) CODES=\(String(describing: e.codes))")
                exit(e.adapter != nil && e.codes != nil ? 0 : 1)
            }
            RunLoop.main.run()
        }
        // Test hook: run the FORScan update (license auto-accepted), exit 0 if FORScan is still there.
        if CommandLine.arguments.contains("--headless-update") {
            let e = Engine()
            e.autoAcceptEula = true
            Task { @MainActor in
                await e.updateForscan()
                print(e.log.joined(separator: "\n"))
                print("FORSCAN=\(e.forscan) VERSION=\(e.installedVersion ?? "none")")
                exit(e.forscan == .done ? 0 : 1)
            }
            RunLoop.main.run()
        }
        // Test hook: write a problem report into OBDOCK_HOME, print its path.
        if CommandLine.arguments.contains("--headless-report") {
            let e = Engine()
            print("REPORT=" + (e.saveReport(open: false)?.path ?? "none"))
            exit(0)
        }
        // Test hook: link drive O:, add the given files, list the folder, exit.
        if let i = CommandLine.arguments.firstIndex(of: "--headless-files") {
            let e = Engine()
            e.linkFilesDrive()
            e.addFiles(CommandLine.arguments[(i + 1)...].map { URL(fileURLWithPath: $0) })
            print(e.log.joined(separator: "\n"))
            print("FILES=" + e.files.map(\.lastPathComponent).joined(separator: ","))
            if let n = e.notice { print("NOTICE=" + n.prefix(40)) }
            exit(0)
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
        Window("OBDock", id: "main") {
            ContentView()
                .environmentObject(engine)
                .frame(width: 480)
                .fixedSize(horizontal: false, vertical: true)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About OBDock") { Self.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Link("OBDock on GitHub", destination: URL(string: "https://github.com/lncch/OBDock")!)
                Button("Report a Problem…") { engine.saveReport() }
                Divider()
                Link("FORScan Website", destination: URL(string: "https://forscan.org")!)
            }
        }
    }

    static func showAbout() {
        let text = """
        Runs FORScan on Apple Silicon Macs with Wine.
        Open source under the MIT license.
        github.com/lncch/OBDock

        FORScan is made by Alexey Savin (forscan.org).
        OBDock is not affiliated with FORScan, Ford or Mazda.
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
            Text("FORScan is made by Alexey Savin (forscan.org). OBDock is not affiliated with FORScan or Ford. It runs the Windows version of FORScan on your Mac.")
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
                Text("OBDock").font(.title2.bold())
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
            }
            .buttonStyle(BrandButtonStyle())
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
            StatusCard()
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
                    Label(engine.busy ? "Opening…" : "Open FORScan", systemImage: "play.fill")
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(engine.busy || engine.serialBusy)
            }
            if engine.updateAvailable, let latest = engine.latestVersion {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                    Text("FORScan \(latest) is out. You have \(engine.installedVersion ?? "an older one").").font(.callout)
                    Spacer()
                    Button("Update") { Task { await engine.updateForscan() } }.disabled(engine.busy)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            CodesCard()
            BackupsCard()
            FilesCard()
        }
    }
}

/// Adapter, battery voltage and FORScan license in one row.
struct StatusCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(engine.port == nil ? Color.secondary.opacity(0.5) : .green)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.port == nil ? "No OBD adapter" : "Adapter connected").fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if engine.running, let mapped = engine.mappedPort, mapped != engine.port {
                    Text("Adapter changed. Quit and reopen FORScan to use it.").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let volts = engine.adapter?.volts {
                    Button { Task { await engine.probeAdapter() } } label: {
                        Label(volts, systemImage: "bolt.fill").font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.plain)
                    .disabled(!engine.canUseAdapter)
                    .help("Car battery voltage at the OBD port. Click to read it again.")
                }
                if let license = engine.license { licenseBadge(license) }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var detail: String {
        guard let port = engine.port else { return "Plug in a USB OBD adapter (ELM327, OBDLink EX, vLinker FS)" }
        if engine.running { return "In use by FORScan · \(port) → COM1" }
        let parts = [engine.chip, engine.adapter?.version].compactMap { $0 }
        return (parts.isEmpty ? [port] : parts).joined(separator: " · ")
    }

    private func licenseBadge(_ l: License) -> some View {
        let (text, color): (String, Color) = {
            guard let days = l.daysLeft, let date = l.expires else { return ("Standard license", .secondary) }
            if days < 0 { return ("Extended expired", .red) }
            return ("Extended · \(date.formatted(.dateTime.day().month()))", days <= 14 ? .orange : .secondary)
        }()
        return Label(text, systemImage: "key.fill").font(.caption).foregroundStyle(color)
            .help(l.expires == nil ? "FORScan's free license" : "FORScan Extended license. Get a new key on forscan.org before it runs out.")
    }
}

/// Reads engine trouble codes straight from the adapter, without FORScan.
struct CodesCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Engine codes", systemImage: "engine.combustion").fontWeight(.medium)
                Spacer()
                Button(engine.codes == .checking ? "Checking…" : "Check") { Task { await engine.checkCodes() } }
                    .disabled(!engine.canUseAdapter)
            }
            switch engine.codes {
            case nil:
                Text(engine.running ? "FORScan is using the adapter. Quit it to check here."
                     : engine.portHeld ? "Another program is using the adapter. Close it to check here."
                     : "Reads the engine's stored and pending codes in a few seconds. Ignition on, switch on HS.")
                    .font(.caption).foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Talking to the car…").font(.caption) }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange)
            case .ok(let stored, let pending) where stored.isEmpty && pending.isEmpty:
                Label("No engine codes", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
            case .ok(let stored, let pending):
                VStack(spacing: 6) {
                    ForEach(stored, id: \.self) { row($0, "Stored") }
                    ForEach(pending.filter { !stored.contains($0) }, id: \.self) { row($0, "Pending") }
                }
                Text("Other modules (ABS, body, steering) need FORScan.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ code: String, _ kind: String) -> some View {
        HStack(spacing: 10) {
            Text(code).font(.system(.body, design: .monospaced).weight(.semibold))
            Text(kind).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background((kind == "Stored" ? Color.orange : Color.secondary).opacity(0.18), in: Capsule())
            Text(DTC.system(code)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Link("Look up", destination: URL(string: "https://www.google.com/search?q=\(code)+OBD2")!).font(.caption)
        }
    }
}

/// As-Built backups (.abt) on drive O:, newest first.
struct BackupsCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("As-Built backups", systemImage: "clock.arrow.circlepath").fontWeight(.medium)
                Spacer()
                Text("\(engine.backups.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if engine.backups.isEmpty {
                Text("None yet. Before you change a setting in FORScan, save that module's As-Built to drive O:. It is your way back.")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                ForEach(engine.backups.prefix(3), id: \.self) { url in
                    Button { engine.reveal(url) } label: {
                        HStack {
                            Text(url.deletingPathExtension().lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(modified(url)).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func modified(_ url: URL) -> String {
        let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Bone on dark, espresso on light: the brand colors from the icon.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let bone = Color(red: 0.929, green: 0.910, blue: 0.863), espresso = Color(red: 0.227, green: 0.149, blue: 0.094)
        return configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(scheme == .dark ? espresso : bone)
            .background(scheme == .dark ? bone : espresso, in: RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// The folder FORScan sees as drive O:. Drop files in, see what FORScan saved there.
struct FilesCard: View {
    @EnvironmentObject var engine: Engine
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Files for FORScan", systemImage: "folder").fontWeight(.medium)
                Spacer()
                Text("drive O:")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(targeted ? Color.accentColor : .secondary)
                Text("Drop license keys, As-Built backups or profiles here").font(.callout)
                Text("In FORScan, open or save files on drive O:").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
            )
            .dropDestination(for: URL.self) { urls, _ in
                engine.addFiles(urls)
                return true
            } isTargeted: { targeted = $0 }

            if !engine.otherFiles.isEmpty {
                VStack(spacing: 0) {
                    ForEach(engine.otherFiles.prefix(3), id: \.self) { url in
                        Button { engine.reveal(url) } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 16, height: 16)
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(url.pathExtension.uppercased()).font(.caption2).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                    if engine.otherFiles.count > 3 {
                        Text("+ \(engine.otherFiles.count - 3) more").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                    }
                }
            }
            HStack {
                Button("Add Files…") { engine.pickFiles() }
                Spacer()
                Button("Open Folder") { engine.openFilesFolder() }
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
