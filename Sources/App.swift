import SwiftUI

@main
struct PlugdApp: App {
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
        // Test hook: the same path as the window: auto-read the adapter at PLUGD_PORT, then press Check.
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
        // Test hook: write a problem report into PLUGD_HOME, print its path.
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
        Window("Plugd", id: "main") {
            ContentView()
                .environmentObject(engine)
                .frame(width: 480)
                .fixedSize(horizontal: false, vertical: true)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Plugd") { Self.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Link("Plugd on GitHub", destination: URL(string: "https://github.com/lncch/Plugd")!)
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
        github.com/lncch/Plugd

        FORScan is made by Alexey Savin (forscan.org).
        Plugd is not affiliated with FORScan, Ford or Mazda.
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
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            .foregroundStyle(.secondary)
        }
        .padding(20)
        // Files can be dropped anywhere on the window once FORScan is set up.
        .dropDestination(for: URL.self) { urls, _ in
            guard engine.ready else { return false }
            engine.addFiles(urls)
            return true
        } isTargeted: { dropTargeted = $0 && engine.ready }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .overlay(Text("Drop to give FORScan these files (drive O:)").font(.headline)
                        .padding(10).background(.regularMaterial, in: Capsule()))
                    .padding(6)
            }
        }
        .sheet(isPresented: Binding(get: { engine.eulaText != nil }, set: { _ in })) {
            EulaSheet(text: engine.eulaText ?? "")
        }
        .alert(engine.notice ?? "", isPresented: Binding(get: { engine.notice != nil }, set: { if !$0 { engine.notice = nil } })) {
            Button("OK") { engine.notice = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("Plugd").font(.headline)
            Spacer()
            Menu {
                Button("Report a Problem…") { engine.saveReport() }
                Link("Which adapter do I need?", destination: Links.adapters)
                Link("Plugd on GitHub", destination: Links.github)
                Divider()
                Button("About Plugd") { PlugdApp.showAbout() }
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Help")
        }
    }
}

enum Links {
    static let github = URL(string: "https://github.com/lncch/Plugd")!
    static let adapters = URL(string: "https://plugd.almoayyad.dev/#adapters")!
}

// MARK: - Setup

struct SetupPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up FORScan on this Mac").font(.title3.weight(.semibold))
                Text("One time, about 2 minutes and a 230 MB download. You will read and accept FORScan's license. macOS may ask for your password to install Rosetta.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                StepRow(title: "Rosetta", detail: "Apple's tool to run Intel apps", state: engine.rosetta)
                StepRow(title: "Wine", detail: "Runs Windows programs (190 MB download)", state: engine.wine)
                StepRow(title: "FORScan", detail: "Downloaded from forscan.org", state: engine.forscan)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Button {
                Task { await engine.setUp() }
            } label: {
                Text(engine.busy ? "Setting up…" : "Set Up")
            }
            .buttonStyle(BrandButtonStyle())
            .disabled(engine.busy)
            Text("FORScan is made by Alexey Savin (forscan.org). Plugd is not affiliated with FORScan or Ford.")
                .font(.caption2).foregroundStyle(.secondary)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            ForscanCard()
            CodesCard()
            FilesCard()
        }
    }
}

/// Adapter, Open FORScan, then license and version: the one thing people open the app for.
struct ForscanCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(engine.port == nil ? Color.secondary.opacity(0.5) : .green).frame(width: 9, height: 9)
                Text(adapterTitle).fontWeight(.medium)
                Spacer()
                if let volts = engine.adapter?.volts {
                    Button { Task { await engine.probeAdapter() } } label: {
                        Label("Car battery \(volts)", systemImage: "bolt.fill").font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!engine.canUseAdapter)
                    .help("Voltage at the OBD port. Click to read it again.")
                }
            }
            .accessibilityElement(children: .combine)
            if engine.port == nil {
                HStack(spacing: 4) {
                    Text("Plug in a USB OBD adapter.").foregroundStyle(.secondary)
                    Link("Which one do I need?", destination: Links.adapters)
                }
                .font(.caption)
            }
            if engine.running, let mapped = engine.mappedPort, mapped != engine.port {
                Text("Adapter changed. Quit and reopen FORScan to use it.").font(.caption).foregroundStyle(.orange)
            }

            if engine.running {
                Button { Task { await engine.quitForscan() } } label: {
                    Label("Quit FORScan", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(engine.busy)
            } else {
                Button { Task { await engine.openForscan() } } label: {
                    Label(engine.busy ? "Starting FORScan…" : "Open FORScan", systemImage: "play.fill")
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(engine.busy || engine.serialBusy)
                if engine.busy {
                    Text("The first start takes about 30 seconds.").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                licenseText
                if let v = engine.installedVersion { Text("·  FORScan \(v)").foregroundStyle(.secondary) }
                Spacer()
                if engine.updateAvailable, let latest = engine.latestVersion {
                    Button("Update to \(latest)") { Task { await engine.updateForscan() } }
                        .controlSize(.small)
                        .disabled(engine.busy)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var adapterTitle: String {
        guard engine.port != nil else { return "No adapter plugged in" }
        if engine.running { return "Adapter in use by FORScan" }
        let name = [engine.chip, engine.adapter?.version].compactMap { $0 }.joined(separator: " · ")
        return name.isEmpty ? "Adapter connected" : "\(name) connected"
    }

    @ViewBuilder private var licenseText: some View {
        if let l = engine.license {
            if let date = l.expires, let days = l.daysLeft {
                if days < 0 {
                    Label("Extended license expired", systemImage: "key.fill").foregroundStyle(.red)
                } else {
                    Label("Extended license until \(date.formatted(.dateTime.day().month()))", systemImage: "key.fill")
                        .foregroundStyle(days <= 14 ? .orange : .secondary)
                }
            } else {
                Label("Standard license", systemImage: "key").foregroundStyle(.secondary)
            }
        }
    }
}

/// Reads engine trouble codes straight from the adapter, without FORScan.
struct CodesCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Engine codes", systemImage: "engine.combustion").fontWeight(.medium)
                if let summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                if let at = engine.codesCheckedAt, engine.codes != .checking {
                    (Text("· ") + Text(at, style: .relative) + Text(" ago")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(engine.codes == .checking ? "Checking…" : "Check") { Task { await engine.checkCodes() } }
                    .disabled(!engine.canUseAdapter)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            switch engine.codes {
            case .checking:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Talking to the car…").font(.caption) }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange)
            case .ok(let stored, let pending) where !(stored.isEmpty && pending.isEmpty):
                VStack(spacing: 6) {
                    ForEach(stored, id: \.self) { row($0, "Stored") }
                    ForEach(pending.filter { !stored.contains($0) }, id: \.self) { row($0, "Pending") }
                }
                Text("Other modules (ABS, body, steering) need FORScan.").font(.caption2).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summary: String? {
        if case .ok(let s, let p) = engine.codes { return s.isEmpty && p.isEmpty ? "No codes" : "\(s.count + p.count) found" }
        return nil
    }

    /// Why Check is greyed out, or what it does before the first check.
    private var hint: String? {
        if engine.port == nil { return "Plug in an adapter first." }
        if engine.running { return "FORScan is using the adapter. Quit it to check here." }
        if engine.portHeld { return "Another program is using the adapter. Close it to check here." }
        if engine.codes == nil { return "Reads the engine's stored and pending codes in a few seconds, with the ignition on." }
        return nil
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

/// The folder FORScan sees as drive O:: license keys, profiles and As-Built backups in one place.
struct FilesCard: View {
    @EnvironmentObject var engine: Engine
    @State private var showBackupHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Files for FORScan", systemImage: "folder").fontWeight(.medium)
                Spacer()
                Text("\(engine.files.count) \(engine.files.count == 1 ? "file" : "files") · \(engine.backups.count) \(engine.backups.count == 1 ? "backup" : "backups")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("FORScan sees this folder as drive O:. Drop files anywhere on this window.")
                .font(.caption).foregroundStyle(.secondary)
            if !engine.files.isEmpty {
                VStack(spacing: 2) {
                    ForEach(engine.files.prefix(4), id: \.self) { url in
                        Button { engine.reveal(url) } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                if Engine.isBackup(url) {
                                    Text("Backup").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                }
                                Spacer()
                                Text(modified(url)).font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                    if engine.files.count > 4 {
                        Text("+ \(engine.files.count - 4) more").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if engine.backups.isEmpty {
                Label("No As-Built backup yet. Save one before you change any setting.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Add Files…") { engine.pickFiles() }
                Button("Open Folder") { engine.openFilesFolder() }
                Spacer()
                Button("How to back up") { showBackupHelp = true }
                    .buttonStyle(.link)
                    .popover(isPresented: $showBackupHelp, arrowEdge: .bottom) { BackupHelp() }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func modified(_ url: URL) -> String {
        let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

struct BackupHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save an As-Built backup").font(.headline)
            Text("1. Open FORScan and connect to the car.")
            Text("2. Go to Configuration and programming, pick the module you will change (for example BCM), and start its As-Built format.")
            Text("3. In the As-Built editor, click Save and choose drive O:.")
            Text("The backup then shows up here. To undo a change, load it the same way and write it back.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 320)
        .padding(16)
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
