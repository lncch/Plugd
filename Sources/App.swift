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
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)
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
    @AppStorage("seenWelcome") private var seenWelcome = false
    // PLUGD_PAGE opens a page directly, for screenshots.
    @State private var page: Page? = Page(rawValue: ProcessInfo.processInfo.environment["PLUGD_PAGE"] ?? "") ?? .home
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if !seenWelcome {
                WelcomeView { seenWelcome = true }
            } else if !engine.ready {
                ScrollView {
                    SetupPanel().frame(maxWidth: 520).padding(40)
                }
                .frame(maxWidth: .infinity)
            } else {
                main
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { helpMenu }
        }
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

    private var main: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.title, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(200)
            .safeAreaInset(edge: .bottom) {
                Text("Plugd \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } detail: {
            let current = page ?? .home
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title).font(.largeTitle.weight(.bold))
                        Text(current.subtitle).foregroundStyle(.secondary)
                    }
                    switch current {
                    case .home: HomePage(page: $page)
                    case .codes: CodesCard()
                    case .files: FilesCard()
                    case .guide: GuidePage()
                    }
                }
                .padding(32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(current.title)
        }
    }

    private var helpMenu: some View {
        Menu {
            if engine.ready { Button("How to Use Plugd") { seenWelcome = true; page = .guide } }
            Button("Show Welcome") { seenWelcome = false }
            Link("Which adapter do I need?", destination: Links.adapters)
            Divider()
            Button("Report a Problem…") { engine.saveReport() }
            Link("Plugd on GitHub", destination: Links.github)
            Button("About Plugd") { PlugdApp.showAbout() }
        } label: {
            Label("Help", systemImage: "questionmark.circle")
        }
        .help("Help")
    }
}

enum Page: String, CaseIterable, Identifiable {
    case home, codes, files, guide
    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .codes: "Engine codes"
        case .files: "Files & backups"
        case .guide: "How to use"
        }
    }

    var subtitle: String {
        switch self {
        case .home: "Plug in your adapter and open FORScan."
        case .codes: "A quick look at the engine's trouble codes, without FORScan."
        case .files: "License keys, profiles and As-Built backups. FORScan sees them as drive O:."
        case .guide: "Short steps for the things people do most."
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .codes: "engine.combustion"
        case .files: "folder"
        case .guide: "book"
        }
    }
}

struct HomePage: View {
    @EnvironmentObject var engine: Engine
    @Binding var page: Page?
    @State private var showLog = false

    var body: some View {
        ForscanCard()
        HStack(spacing: 12) {
            SummaryTile(title: "Engine codes", value: codesValue, icon: "engine.combustion", warn: codesWarn) { page = .codes }
            SummaryTile(title: "Backups", value: engine.backups.isEmpty ? "None yet" : "\(engine.backups.count) saved",
                        icon: "externaldrive", warn: engine.backups.isEmpty) { page = .files }
        }
        DisclosureGroup("Details", isExpanded: $showLog) {
            ScrollView {
                Text(engine.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 120)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var codesValue: String {
        switch engine.codes {
        case .ok(let s, let p): s.isEmpty && p.isEmpty ? "No codes" : "\(s.count + p.count) found"
        case .checking: "Checking…"
        case .failed: "Check failed"
        case nil: "Not checked"
        }
    }

    private var codesWarn: Bool {
        if case .ok(let s, let p) = engine.codes { return !(s.isEmpty && p.isEmpty) }
        return false
    }
}

/// A small card on Home that opens another page.
struct SummaryTile: View {
    let title: String
    let value: String
    let icon: String
    let warn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.headline).foregroundStyle(warn ? .orange : .primary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Welcome

/// Shown once before setup. "Show Welcome" in the Help menu brings it back.
struct WelcomeView: View {
    let done: () -> Void
    // PLUGD_WELCOME_STEP opens a page directly, for screenshots.
    @State private var step = Int(ProcessInfo.processInfo.environment["PLUGD_WELCOME_STEP"] ?? "") ?? 0
    private let last = 2

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Group {
                switch step {
                case 0: intro
                case 1: needs
                default: how
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 40)
            Spacer()
            HStack {
                Button("Skip", action: done).buttonStyle(.link).opacity(step < last ? 1 : 0)
                    .frame(width: 220, alignment: .leading)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0...last, id: \.self) { i in
                        Circle().fill(i == step ? Color.primary : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityLabel("Page \(step + 1) of \(last + 1)")
                Spacer()
                HStack(spacing: 10) {
                    if step > 0 { Button("Back") { step -= 1 }.controlSize(.large) }
                    Button(step < last ? "Continue" : "Get Started") { step < last ? (step += 1) : done() }
                        .buttonStyle(BrandButtonStyle())
                        .frame(width: 130)
                        .keyboardShortcut(.defaultAction)
                }
                .frame(width: 220, alignment: .trailing)
            }
            .padding(24)
        }
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Welcome to Plugd").font(.largeTitle.weight(.bold))
            Text("FORScan on your Mac. Read codes, change car settings and keep backups, with no Windows laptop.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var needs: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What you need").font(.largeTitle.weight(.bold))
            WelcomeRow(icon: "cable.connector", title: "A USB OBD adapter",
                       detail: "An ELM327 with an HS/MS switch works. It plugs in under the dashboard.")
            WelcomeRow(icon: "car.fill", title: "A Ford, Lincoln or Mazda",
                       detail: "Turn the ignition on. The engine can stay off.")
            WelcomeRow(icon: "key.fill", title: "A FORScan license",
                       detail: "Reading works without one. To change settings, get a free Extended license at forscan.org.")
            Link("Which adapter do I need?", destination: Links.adapters).font(.callout)
        }
    }

    private var how: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("How it works").font(.largeTitle.weight(.bold))
            WelcomeRow(icon: "1.circle.fill", title: "Set up once", detail: "Plugd downloads FORScan and what it needs. About 2 minutes.")
            WelcomeRow(icon: "2.circle.fill", title: "Plug in and open FORScan", detail: "Plugd finds your adapter and connects FORScan to it.")
            WelcomeRow(icon: "3.circle.fill", title: "Back up before you change anything", detail: "Save an As-Built backup. Plugd keeps it safe and shows it under Files.")
        }
    }
}

struct WelcomeRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title).foregroundStyle(.secondary).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - How to use

struct GuidePage: View {
    var body: some View {
        GuideCard(title: "Connect to your car", icon: "car.fill", steps: [
            "Plug the adapter into the OBD port under the dashboard, then into your Mac.",
            "Turn the ignition on. Set the adapter switch to HS.",
            "On Home, click Open FORScan. In FORScan, click Connect at the bottom.",
            "If FORScan asks you to switch to MS or HS, flip the switch and click OK.",
        ])
        GuideCard(title: "Load a license key", icon: "key.fill", steps: [
            "Drop the .key file on the Plugd window.",
            "In FORScan, open About (the i button) and click Load key.",
            "Pick the key on drive O:. You do this once; the key stays.",
        ])
        GuideCard(title: "Back up before a change", icon: "externaldrive", steps: [
            "Connect, then open Configuration and programming.",
            "Pick the module you will change (for example BCM) and start its As-Built format.",
            "Click Save and choose drive O:. The backup shows up under Files & backups.",
        ])
        GuideCard(title: "Undo a change", icon: "arrow.uturn.backward", steps: [
            "Open the same module's As-Built format.",
            "Click Load, pick your backup on drive O:, then Write.",
        ])
        GuideCard(title: "Stay safe while writing", icon: "bolt.fill", steps: [
            "Connect a battery charger before you write settings.",
            "Do not turn the car off or unplug the adapter during a write.",
        ])
    }
}

struct GuideCard: View {
    let title: String
    let icon: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary).frame(width: 14)
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
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
            Text("Drop files anywhere on this window, or use Add Files.")
                .font(.caption).foregroundStyle(.secondary)
            if !engine.files.isEmpty {
                VStack(spacing: 2) {
                    ForEach(engine.files, id: \.self) { url in
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
