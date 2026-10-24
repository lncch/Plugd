import AppKit
import Foundation

/// FORScan's Extended license, read from the Wine registry. `expires == nil` means the free standard license.
struct License: Equatable {
    let expires: Date?

    var daysLeft: Int? {
        expires.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: $0).day ?? 0 }
    }
}

extension Engine {
    // MARK: - Adapter

    /// Called after every poll. Reads the adapter when it appears or when FORScan lets go of it.
    func pollChanged(oldPort: String?, wasRunning: Bool) {
        if port != oldPort {
            adapter = nil
            codes = nil
            codesCheckedAt = nil
            chip = port.map(Self.isUSB) == true ? Self.usbChip() : nil
            if port != nil { Task { await probeAdapter() } }
        }
        if wasRunning && !running {
            readLicense()
            Task { await probeAdapter() }
        }
    }

    /// Reads the adapter's ELM version and the car's battery voltage.
    func probeAdapter() async {
        portHeld = Self.portHeld(port)
        guard let port, canUseAdapter else { return }
        serialBusy = true
        defer { serialBusy = false }
        let info = await Task.detached { ELM.probe(port) }.value
        adapter = info
        say(info.map { "Adapter: \($0.version), battery \($0.volts ?? "?")" } ?? "Adapter at \(port) did not answer")
    }

    func checkCodes() async {
        portHeld = Self.portHeld(port)
        guard let port, canUseAdapter else { return }
        serialBusy = true
        defer { serialBusy = false }
        codes = .checking
        let result = await Task.detached { ELM.readCodes(port) }.value
        codes = result
        codesCheckedAt = Date()
        switch result {
        case .ok(let s, let p): say("Engine codes: \(s.isEmpty ? "none stored" : s.joined(separator: ", "))\(p.isEmpty ? "" : ", pending \(p.joined(separator: ", "))")")
        case .failed(let m): say("Code check: \(m)")
        case .checking: break
        }
    }

    /// FORScan, or any other program, must not be holding the port.
    var canUseAdapter: Bool {
        port != nil && !portHeld && !running && !serialBusy && !busy
    }

    /// Another program has the port open. Checked in poll(), not on every redraw.
    nonisolated static func portHeld(_ port: String?) -> Bool {
        // The test emulator (PLUGD_PORT) always holds its own pty open, so skip the check there.
        guard let port, ProcessInfo.processInfo.environment["PLUGD_PORT"] == nil else { return false }
        return !shell("/usr/sbin/lsof", ["-t", port]).out.isEmpty
    }

    /// The USB-serial chip inside the adapter, from its USB vendor id.
    nonisolated static func usbChip() -> String? {
        let chips = [0x1A86: "CH340", 0x0403: "FTDI", 0x10C4: "CP210x", 0x067B: "PL2303"]
        let out = shell("/usr/sbin/ioreg", ["-p", "IOUSB", "-l", "-w0"]).out
        for line in out.split(separator: "\n") where line.contains("\"idVendor\" = ") {
            if let v = Int(line.split(separator: "=").last!.trimmingCharacters(in: .whitespaces)), let c = chips[v] { return c }
        }
        return nil
    }

    // MARK: - License

    func readLicense() {
        guard let reg = try? String(contentsOf: prefix.appendingPathComponent("user.reg"), encoding: .utf8) else {
            license = nil
            return
        }
        let f = Self.isoFormatter("yyyy-MM-dd")
        license = License(expires: Self.forscanRegistry(reg)["ExpirationDate"].flatMap(f.date))
    }

    /// FORScan writes Gregorian dates; the Mac may use another calendar (e.g. Hijri).
    nonisolated static func isoFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    /// Values under one key of a Wine .reg file; by default HKCU\Software\Astech\FORScan in user.reg.
    nonisolated static func forscanRegistry(_ reg: String, key: String = #"Software\\Astech\\FORScan"#) -> [String: String] {
        var inside = false
        var values: [String: String] = [:]
        for line in reg.split(separator: "\n") {
            if line.hasPrefix("[") {
                if inside { break }
                inside = line.hasPrefix("[\(key)]")
                continue
            }
            guard inside, line.hasPrefix("\""), line.hasSuffix("\""), let eq = line.range(of: "\"=\"") else { continue }
            values[String(line[line.index(after: line.startIndex)..<eq.lowerBound])] = String(line[eq.upperBound...].dropLast())
        }
        return values
    }

    // MARK: - FORScan updates

    nonisolated static func installerLink(_ page: String) -> URL? {
        page.range(of: #"download/FORScanSetup[0-9.]+\.release\.exe"#, options: .regularExpression)
            .map { URL(string: String(page[$0]), relativeTo: forscanPage)!.absoluteURL }
    }

    nonisolated static func setupVersion(_ name: String) -> String? {
        name.range(of: #"(?<=FORScanSetup)[0-9.]+(?=\.release\.exe)"#, options: .regularExpression).map { String(name[$0]) }
    }

    nonisolated static func older(_ a: String, _ b: String) -> Bool { a.compare(b, options: .numeric) == .orderedAscending }

    func readInstalledVersion() {
        guard forscan == .done else { installedVersion = nil; return }
        if let v = try? String(contentsOf: base.appendingPathComponent("forscan-version.txt"), encoding: .utf8) {
            installedVersion = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        // 0.2.x did not write that file, but the installer it used is still in downloads.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
        installedVersion = names.compactMap(Self.setupVersion).max(by: Self.older)
    }

    func checkForscanUpdate() async {
        guard let (html, _) = try? await URLSession.shared.data(from: Self.forscanPage),
              let link = Self.installerLink(String(decoding: html, as: UTF8.self)) else { return }
        latestVersion = Self.setupVersion(link.lastPathComponent)
    }

    var updateAvailable: Bool {
        guard let installedVersion, let latestVersion else { return false }
        return Self.older(installedVersion, latestVersion)
    }

    func updateForscan() async {
        if running { await quitForscan() }
        busy = true
        defer { busy = false; refreshSteps(); readInstalledVersion() }
        do {
            try await installForscan()
            say("FORScan updated to \(latestVersion ?? "the latest version")")
        } catch {
            say("Update stopped: \(error.localizedDescription)")
        }
    }

    // MARK: - Backups

    var backups: [URL] { files.filter(Self.isBackup) }

    nonisolated static func isBackup(_ url: URL) -> Bool { ["abt", "ab"].contains(url.pathExtension.lowercased()) }

    // MARK: - Problem report

    /// Writes a report with Plugd's and FORScan's logs, with the license key and hardware id removed.
    @discardableResult
    func saveReport(open: Bool = true) -> URL? {
        let reg = (try? String(contentsOf: prefix.appendingPathComponent("user.reg"), encoding: .utf8)).map { Self.forscanRegistry($0) } ?? [:]
        let info = Bundle.main.infoDictionary
        var r = """
        Plugd \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?")) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Rosetta \(rosetta == .done ? "yes" : "no") · Wine \(wine == .done ? "yes" : "no") · FORScan \(installedVersion ?? "not installed")
        Adapter: \(port ?? "none") \(chip ?? "") \(adapter?.version ?? "") \(adapter?.volts ?? "")
        License: \(license?.expires == nil ? "standard" : "extended")

        --- Plugd log ---
        \(log.joined(separator: "\n"))
        """
        if let flog = forscanLog(), let data = try? Data(contentsOf: flog) {
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            r += "\n\n--- FORScan log, last 1500 lines ---\n" + lines.suffix(1500).joined(separator: "\n")
        }
        r = Self.redact(r, secrets: [reg["Key"], reg["Id"]].compactMap { $0 })

        let f = Self.isoFormatter("yyyy-MM-dd HHmm")
        let dir = ProcessInfo.processInfo.environment["PLUGD_HOME"] != nil
            ? base : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let out = dir.appendingPathComponent("Plugd report \(f.string(from: Date())).txt")
        do { try r.write(to: out, atomically: true, encoding: .utf8) } catch {
            notice = "Could not save the report: \(error.localizedDescription)"
            return nil
        }
        say("Report saved: \(out.path)")
        if open {
            reveal(out)
            NSWorkspace.shared.open(URL(string: "https://github.com/lncch/Plugd/issues/new")!)
            notice = "Report saved on your Desktop. The license key and hardware id were removed.\n\nAttach it to the GitHub issue that just opened."
        }
        return out
    }

    func forscanLog() -> URL? {
        let users = driveC.appendingPathComponent("users")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? []
        return names.map { users.appendingPathComponent("\($0)/AppData/Roaming/FORScan/log/FORScan.log") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated static func redact(_ text: String, secrets: [String], user: String = NSUserName()) -> String {
        var t = text
        // The Mac user name shows up in paths and in FORScan's "User name:" line.
        if user.count >= 2 {
            t = t.replacingOccurrences(of: #"\b"# + NSRegularExpression.escapedPattern(for: user) + #"\b"#,
                                       with: "[user]", options: [.regularExpression, .caseInsensitive])
        }
        // VINs: 17 letters and digits (no I, O or Q), with at least one of each.
        t = t.replacingOccurrences(of: #"\b(?=[A-HJ-NPR-Z0-9]*[A-HJ-NPR-Z])(?=[A-HJ-NPR-Z0-9]*[0-9])[A-HJ-NPR-Z0-9]{17}\b"#,
                                   with: "[VIN]", options: .regularExpression)
        for s in secrets where s.count >= 8 { t = t.replacingOccurrences(of: s, with: "[removed]") }
        // FORScan logs the key as "Registry Key: …" and "Extended License key: …".
        t = t.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let r = line.range(of: "key:", options: .caseInsensitive) else { return String(line) }
            return line[..<r.upperBound] + " [removed]"
        }.joined(separator: "\n")
        return t.replacingOccurrences(of: #"[A-Za-z0-9+/=]{40,}"#, with: "[removed]", options: .regularExpression)
    }

    nonisolated static func redactSelfTest() -> [String] {
        let key = String(repeating: "Ab3+", count: 20), id = "KLZwFAKEid123456"
        let log = "12:00 [GUI] Registry Key: \(key)\n12:01 [GUI] Extended License key: \(key)\nId=\(id) adapter ok\nother \(key)"
            + "\nUser name: jdoe\nC:\\users\\jdoe\\AppData /Users/jdoe/Documents\nVIN: 1FAHP2E89DG123456 module 7E0"
        let out = redact(log, secrets: [key, id], user: "jdoe")
        var fails: [String] = []
        if out.contains(key) || out.contains("Ab3+Ab3+") { fails.append("key left in report") }
        if out.contains(id) { fails.append("hardware id left in report") }
        if !out.contains("adapter ok") { fails.append("normal text removed") }
        if out.contains("jdoe") { fails.append("user name left in report") }
        if out.contains("1FAHP2E89DG123456") { fails.append("VIN left in report") }
        if !out.contains("module 7E0") || !out.contains("/Users/[user]/Documents") { fails.append("normal text removed") }
        let reg = "[Software\\\\Astech\\\\FORScan] 1\n\"ExpirationDate\"=\"2026-12-18\"\n[Next]\n\"ExpirationDate\"=\"1999-01-01\"\n"
        let date = forscanRegistry(reg)["ExpirationDate"].flatMap(isoFormatter("yyyy-MM-dd").date)
        if date.map({ Calendar(identifier: .gregorian).component(.year, from: $0) }) != 2026 { fails.append("license date \(String(describing: date))") }
        let ports = "[Software\\\\Wine\\\\Ports] 1\n#time=1\n\"COM1\"=\"/dev/cu.usbserial-120\"\n"
        if forscanRegistry(ports, key: #"Software\\Wine\\Ports"#)["COM1"] != "/dev/cu.usbserial-120" { fails.append("COM1 not read") }
        return fails
    }
}
