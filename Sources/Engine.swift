import AppKit
import Foundation

enum StepState: Equatable {
    case waiting, running(String), done, failed(String)
}

/// Everything OBDock does outside its window: Rosetta, Wine, FORScan, the adapter.
@MainActor
final class Engine: ObservableObject {
    // Wine build verified with FORScan and a real car on 2026-10-18.
    static let wineURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-staging-11.18-osx64.tar.xz")!
    static let forscanPage = URL(string: "https://forscan.org/download.html")!
    static let portPrefixes = ["cu.usbserial", "cu.wchusbserial", "cu.usbmodem", "cu.SLAB_USBtoUART"]

    let base: URL
    var wineApp: URL { base.appendingPathComponent("wine/Wine Staging.app") }
    var wineBin: URL { wineApp.appendingPathComponent("Contents/Resources/wine/bin") }
    var prefix: URL { base.appendingPathComponent("prefix") }
    var driveC: URL { prefix.appendingPathComponent("drive_c") }
    var forscanDir: URL { driveC.appendingPathComponent("Program Files (x86)/FORScan") }
    var forscanExe: URL { forscanDir.appendingPathComponent("FORScan.exe") }
    var downloads: URL { base.appendingPathComponent("downloads") }

    @Published var rosetta: StepState = .waiting
    @Published var wine: StepState = .waiting
    @Published var forscan: StepState = .waiting
    @Published var busy = false
    @Published var port: String?
    @Published var running = false
    @Published var mappedPort: String?
    @Published var eulaText: String?
    @Published var notice: String?
    @Published var log: [String] = []

    private var eulaAnswer: CheckedContinuation<Bool, Never>?
    private var timer: Timer?

    var ready: Bool { rosetta == .done && wine == .done && forscan == .done }

    init() {
        // OBDOCK_HOME lets a test run start from an empty folder.
        if let home = ProcessInfo.processInfo.environment["OBDOCK_HOME"] {
            base = URL(fileURLWithPath: home)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            base = support.appendingPathComponent("OBDock")
            // The app was called ScanBridge in 0.1.0; keep that setup instead of downloading again.
            let old = support.appendingPathComponent("ScanBridge")
            if !FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: old.path) {
                try? FileManager.default.moveItem(at: old, to: base)
            }
        }
        refreshSteps()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    // MARK: - State

    func refreshSteps() {
        let fm = FileManager.default
        rosetta = Self.rosettaInstalled() ? .done : .waiting
        wine = fm.fileExists(atPath: wineBin.appendingPathComponent("wine").path)
            && fm.fileExists(atPath: driveC.path) ? .done : .waiting
        forscan = fm.fileExists(atPath: forscanExe.path) ? .done : .waiting
    }

    func poll() {
        // OBDOCK_PORT lets a test use a fake adapter (e.g. ELM327-emulator's pty).
        if let fake = ProcessInfo.processInfo.environment["OBDOCK_PORT"] {
            port = fake
            running = Self.forscanRunning(in: forscanDir)
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        port = names.filter { n in Self.portPrefixes.contains { n.hasPrefix($0) } }.sorted().first.map { "/dev/" + $0 }
        running = Self.forscanRunning(in: forscanDir)
    }

    nonisolated static func rosettaInstalled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-x86_64", "/usr/bin/true"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// True only for a FORScan started from this folder, not one from another Wine setup.
    nonisolated static func forscanRunning(in dir: URL) -> Bool {
        // realpath, not resolvingSymlinksInPath: the latter turns /private/tmp into /tmp, lsof does not.
        guard let real = realpath(dir.path, nil) else { return false }
        defer { free(real) }
        let want = "n" + String(cString: real)
        let out = shell("/usr/sbin/lsof", ["-a", "-d", "cwd", "-c", "FORScan", "-Fn"]).out
        return out.split(separator: "\n").contains { $0 == want }
    }

    // MARK: - Setup

    func setUp() async {
        busy = true
        defer { busy = false; refreshSteps() }
        do {
            if rosetta != .done { try await installRosetta() }
            if wine != .done { try await installWine() }
            if forscan != .done { try await installForscan() }
        } catch {
            say("Stopped: \(error.localizedDescription)")
        }
    }

    private func installRosetta() async throws {
        rosetta = .running("Installing Rosetta…")
        var r = await Self.run("/usr/sbin/softwareupdate", ["--install-rosetta", "--agree-to-license"])
        if !Self.rosettaInstalled() {
            // Needs an admin password on some Macs.
            r = await Self.run("/usr/bin/osascript", ["-e",
                "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"])
        }
        guard Self.rosettaInstalled() else {
            rosetta = .failed("Rosetta did not install")
            throw Fail("Rosetta: \(r.out.suffix(300))")
        }
        rosetta = .done
        say("Rosetta ready")
    }

    private func installWine() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let tarball = downloads.appendingPathComponent("wine.tar.xz")
        if !fm.fileExists(atPath: wineBin.appendingPathComponent("wine").path) {
            try await download(Self.wineURL, to: tarball, label: "Downloading Wine") { self.wine = .running($0) }
            wine = .running("Unpacking Wine…")
            let wineDir = base.appendingPathComponent("wine")
            try fm.createDirectory(at: wineDir, withIntermediateDirectories: true)
            let r = await Self.run("/usr/bin/tar", ["-xf", tarball.path, "-C", wineDir.path])
            guard r.code == 0 else { wine = .failed("Unpack failed"); throw Fail("tar: \(r.out.suffix(300))") }
            _ = await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", wineApp.path])
            try? fm.removeItem(at: tarball)
        }
        wine = .running("Creating Windows folder…")
        let r = await wineRun("wineboot", ["--init"])
        guard fm.fileExists(atPath: driveC.path) else { wine = .failed("Wine did not start"); throw Fail("wineboot: \(r.out.suffix(300))") }
        // No crash dialogs if a Windows program dies.
        _ = await wineRun("wine", ["reg", "add", "HKCU\\Software\\Wine\\WineDbg", "/v", "ShowCrashDialog", "/t", "REG_DWORD", "/d", "0", "/f"])
        wine = .done
        say("Wine ready")
    }

    private func installForscan() async throws {
        let fm = FileManager.default
        forscan = .running("Finding the latest FORScan…")
        let (html, _) = try await URLSession.shared.data(from: Self.forscanPage)
        let page = String(decoding: html, as: UTF8.self)
        guard let m = page.range(of: #"download/FORScanSetup[0-9.]+\.release\.exe"#, options: .regularExpression) else {
            forscan = .failed("Download link not found")
            throw Fail("No installer link on forscan.org")
        }
        let installerURL = URL(string: String(page[m]), relativeTo: Self.forscanPage)!.absoluteURL
        let installer = downloads.appendingPathComponent(installerURL.lastPathComponent)
        if !fm.fileExists(atPath: installer.path) {
            try await download(installerURL, to: installer, label: "Downloading FORScan") { self.forscan = .running($0) }
        }
        say("Installer: \(installer.lastPathComponent)")

        // Unpack locally to read the license, and as a fallback for the install itself.
        forscan = .running("Reading the license…")
        let unpacked = base.appendingPathComponent("unpacked")
        try? fm.removeItem(at: unpacked)
        let ie = await Self.run(Self.innoextract, ["-s", "--language", "eng", "-d", unpacked.path, installer.path])
        guard ie.code == 0 else { forscan = .failed("Could not open the installer"); throw Fail("innoextract: \(ie.out.suffix(300))") }
        let eula = (try? String(contentsOf: unpacked.appendingPathComponent("app/FORScan.EndUser.License.txt"), encoding: .utf8))
            ?? "FORScan license file not found in the installer."

        guard await askEula(eula) else {
            forscan = .waiting
            throw Fail("License not accepted")
        }

        // 1. The official installer. Wine 11 crashes inside it today, but try first in case a later Wine fixes it.
        forscan = .running("Running the official installer…")
        _ = await wineRun("wine", [installer.path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"], timeout: 120)
        // When it crashes, its helper process hangs on; stop everything in this Wine folder.
        _ = await wineRun("wineserver", ["-k"])
        if fm.fileExists(atPath: forscanExe.path) {
            say("Official installer worked")
        } else {
            // 2. Fallback: place the installer's own files, unchanged.
            say("Official installer failed under Wine, copying its files instead")
            forscan = .running("Copying FORScan files…")
            try? fm.removeItem(at: forscanDir)
            try fm.createDirectory(at: forscanDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: unpacked.appendingPathComponent("app"), to: forscanDir)
            try trimTrailingSpaces(in: forscanDir)
        }
        try? fm.removeItem(at: unpacked)
        guard fm.fileExists(atPath: forscanExe.path) else { forscan = .failed("FORScan.exe missing"); throw Fail("FORScan.exe missing") }
        forscan = .done
        say("FORScan ready")
    }

    /// innoextract keeps a trailing space in "FORScan.exe ", which Wine cannot open.
    private func trimTrailingSpaces(in dir: URL) throws {
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: dir.path) where name != name.trimmingCharacters(in: .whitespaces) {
            try fm.moveItem(at: dir.appendingPathComponent(name),
                            to: dir.appendingPathComponent(name.trimmingCharacters(in: .whitespaces)))
        }
    }

    /// Test runs only (--headless-setup).
    var autoAcceptEula = false

    private func askEula(_ text: String) async -> Bool {
        if autoAcceptEula {
            say("License shown to tester: \(text.prefix(60))…")
            return true
        }
        return await withCheckedContinuation { c in
            eulaAnswer = c
            eulaText = text
        }
    }

    func answerEula(_ accepted: Bool) {
        eulaText = nil
        eulaAnswer?.resume(returning: accepted)
        eulaAnswer = nil
    }

    // MARK: - FORScan

    func openForscan() async {
        guard !running else { return }
        busy = true
        defer { busy = false }
        if let port, port != mappedPort {
            _ = await wineRun("wine", ["reg", "add", "HKLM\\Software\\Wine\\Ports", "/v", "COM1", "/t", "REG_SZ", "/d", port, "/f"])
            // Wine reads the port list when it starts, so restart it.
            _ = await wineRun("wineserver", ["-k"])
            mappedPort = port
            say("COM1 → \(port)")
        } else if port == nil {
            say("No adapter plugged in. FORScan opens but cannot connect.")
        }
        let p = Process()
        p.executableURL = wineBin.appendingPathComponent("wine")
        p.arguments = ["FORScan.exe"]
        p.currentDirectoryURL = forscanDir
        p.environment = wineEnv()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); say("FORScan starting…") } catch { say("Could not start FORScan: \(error.localizedDescription)"); return }
        // The first start under Rosetta can take 20 s or more.
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            poll()
            if running { say("FORScan is open"); return }
        }
        say("FORScan has not appeared after 60 s. Check the Dock for 'wine'.")
    }

    func quitForscan() async {
        _ = await wineRun("wineserver", ["-k"])
        mappedPort = nil
        poll()
        say("FORScan closed")
    }

    func importKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.message = "Choose your FORScan license key (.key)"
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let dst = driveC.appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.removeItem(at: dst)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            notice = "Key copied to C:\\\(src.lastPathComponent)\n\nIn FORScan: click the last icon on the left (About), then Load key, then pick it from C:."
        } catch {
            notice = "Could not copy the key: \(error.localizedDescription)"
        }
    }

    func revealFiles() { NSWorkspace.shared.activateFileViewerSelecting([base]) }

    // MARK: - Helpers

    private func say(_ s: String) { log.append(s) }

    private func wineEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        env["MVK_CONFIG_LOG_LEVEL"] = "0"
        return env
    }

    private func wineRun(_ tool: String, _ args: [String], timeout: TimeInterval = 300) async -> (code: Int32, out: String) {
        await Self.run(wineBin.appendingPathComponent(tool).path, args, env: wineEnv(), timeout: timeout)
    }

    private func download(_ url: URL, to file: URL, label: String, progress: @escaping (String) -> Void) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let total = (try? await URLSession.shared.data(for: req).1.expectedContentLength) ?? -1
        let tmp = file.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: tmp)
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
                if total > 0 {
                    progress("\(label)… \(min(99, Int(Double(size) / Double(total) * 100)))% of \(total / 1_000_000) MB")
                } else {
                    progress("\(label)… \(size / 1_000_000) MB")
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        let r = await Self.run("/usr/bin/curl", ["-fsSL", "-o", tmp.path, url.absoluteString], timeout: 3600)
        watcher.cancel()
        guard r.code == 0 else { throw Fail("\(label) failed: \(r.out.suffix(200))") }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
    }

    nonisolated static var innoextract: String {
        Bundle.main.resourceURL!.appendingPathComponent("bin/innoextract").path
    }

    nonisolated static func shell(_ exe: String, _ args: [String], env: [String: String]? = nil,
                                  timeout: TimeInterval = 300) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let env { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let reader = DispatchQueue(label: "read")
        reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile() }
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { p.terminate() }
        p.waitUntilExit()
        reader.sync {}
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    nonisolated static func run(_ exe: String, _ args: [String], env: [String: String]? = nil,
                                timeout: TimeInterval = 300) async -> (code: Int32, out: String) {
        await Task.detached { shell(exe, args, env: env, timeout: timeout) }.value
    }
}

struct Fail: LocalizedError {
    let msg: String
    init(_ m: String) { msg = m }
    var errorDescription: String? { msg }
}
