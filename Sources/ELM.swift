import Darwin
import Foundation

/// Talks to an ELM327 adapter over its serial port. Only used while FORScan is closed.
struct ELM {
    struct Info: Sendable, Equatable {
        var version: String
        var volts: String?
    }

    enum Codes: Sendable, Equatable {
        case checking
        case ok(stored: [String], pending: [String])
        case failed(String)
    }

    let fd: Int32

    /// Opens the port and resets the adapter. Cheap ELM327 clones run at 38400, some at 115200.
    static func open(_ path: String) -> ELM? {
        for baud in [38400, 115200] {
            let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else { return nil }
            var t = termios()
            tcgetattr(fd, &t)
            cfmakeraw(&t)
            cfsetspeed(&t, speed_t(baud))
            t.c_cflag |= tcflag_t(CLOCAL | CREAD)
            tcsetattr(fd, TCSANOW, &t)
            let elm = ELM(fd: fd)
            if elm.send("ATZ", timeout: 3).contains("ELM") {
                _ = elm.send("ATE0")
                return elm
            }
            Darwin.close(fd)
        }
        return nil
    }

    func close() { Darwin.close(fd) }

    /// Sends one command and returns the reply lines, without the echo, prompt or "SEARCHING...".
    func send(_ cmd: String, timeout: TimeInterval = 2) -> String {
        tcflush(fd, TCIFLUSH)
        let bytes = Array((cmd + "\r").utf8)
        _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 256)
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, out.last != UInt8(ascii: ">") {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&p, 1, 50) > 0 else { continue }
            let n = read(fd, &buf, buf.count)
            if n > 0 { out += buf[0..<n] }
        }
        return String(decoding: out, as: UTF8.self).elmLines
            .filter { $0 != cmd && $0 != "SEARCHING..." }
            .joined(separator: "\n")
    }

    static func probe(_ path: String) -> Info? {
        guard let e = open(path) else { return nil }
        defer { e.close() }
        let version = e.send("ATI").elmLines.first { $0.contains("ELM") } ?? "ELM327"
        let volts = e.send("ATRV").elmLines.first { $0.hasSuffix("V") }.map { String($0.dropLast()) + " V" }
        return Info(version: version, volts: volts)
    }

    /// Reads stored (mode 03) and pending (mode 07) OBD-II codes. Only emission-related modules answer these.
    static func readCodes(_ path: String) -> Codes {
        guard let e = open(path) else { return .failed("The adapter did not answer. Unplug it and plug it back in.") }
        defer { e.close() }
        _ = e.send("ATSP0")
        // The first request makes the adapter search for the car's protocol; that can take 10 s.
        guard e.send("0100", timeout: 15).contains("41 00") else {
            return .failed("No answer from the car. Turn the ignition on and set the adapter switch to HS.")
        }
        let proto = e.send("ATDPN").elmLines.first ?? ""
        let can = "6789".contains(proto.last ?? "0")
        _ = e.send(can ? "ATH1" : "ATH0")
        let stored = DTC.parse(e.send("03", timeout: 5), mode: 0x43, can: can)
        let pending = DTC.parse(e.send("07", timeout: 5), mode: 0x47, can: can)
        _ = e.send("ATH0")
        return .ok(stored: stored, pending: pending)
    }
}

enum DTC {
    /// Turns an ELM327 reply into codes like "P0133".
    /// CAN replies come with headers on, so frames from several modules and multi-frame replies can be put back together.
    static func parse(_ text: String, mode: UInt8, can: Bool) -> [String] {
        var payloads: [[UInt8]] = []
        if can {
            var frames: [String: (len: Int, data: [UInt8])] = [:]
            var order: [String] = []
            for line in text.elmLines {
                var tok = line.split(separator: " ").map(String.init)
                let header: String
                if tok.first?.count == 3 { header = tok.removeFirst() }           // 11-bit id, e.g. 7E8
                else if tok.count > 5 { header = tok[0..<4].joined(); tok.removeFirst(4) }  // 29-bit id, e.g. 18 DA F1 10
                else { continue }
                let b = tok.compactMap { UInt8($0, radix: 16) }
                guard b.count == tok.count, let pci = b.first else { continue }
                switch pci >> 4 {
                case 0: frames[header] = (Int(pci & 0x0F), Array(b.dropFirst())); order.append(header)
                case 1 where b.count > 1: frames[header] = ((Int(pci & 0x0F) << 8) | Int(b[1]), Array(b.dropFirst(2))); order.append(header)
                case 2: frames[header]?.data += b.dropFirst()
                default: break
                }
            }
            // On CAN the mode byte is followed by a count byte.
            payloads = order.compactMap { h in frames[h].map { Array($0.data.prefix($0.len)) } }
                .filter { $0.first == mode }.map { Array($0.dropFirst(2)) }
        } else {
            for line in text.elmLines {
                let b = line.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                if b.first == mode { payloads.append(Array(b.dropFirst())) }
            }
        }
        var codes: [String] = []
        for p in payloads {
            for i in stride(from: 0, to: p.count - 1, by: 2) where p[i] != 0 || p[i + 1] != 0 {
                let c = name(p[i], p[i + 1])
                if !codes.contains(c) { codes.append(c) }
            }
        }
        return codes
    }

    static func name(_ a: UInt8, _ b: UInt8) -> String {
        ["P", "C", "B", "U"][Int(a >> 6)] + String(format: "%d%X%02X", (a >> 4) & 3, a & 0x0F, b)
    }

    static func system(_ code: String) -> String {
        ["P": "Engine and transmission", "C": "Chassis", "B": "Body", "U": "Network"][String(code.prefix(1))] ?? ""
    }

    /// Returns the cases that failed (empty when all pass). Run with --self-test.
    static func selfTest() -> [String] {
        let cases: [(String, Bool, [String])] = [
            ("7E8 06 43 02 01 33 02 44", true, ["P0133", "P0244"]),
            ("7E8 10 0A 43 04 01 33 02 44\n7E8 21 C1 23 D4 56 00 00 00", true, ["P0133", "P0244", "U0123", "U1456"]),
            ("7E8 04 43 01 01 33\n7E9 04 43 01 07 00", true, ["P0133", "P0700"]),
            ("7E8 02 43 00", true, []),
            ("18 DA F1 10 04 43 01 01 33", true, ["P0133"]),
            ("NO DATA", true, []),
            ("43 01 33 00 00 00 00", false, ["P0133"]),
            ("43 01 33 81 22 00 00\n43 C1 23 00 00 00 00", false, ["P0133", "B0122", "U0123"]),
        ]
        return cases.compactMap { text, can, want in
            let got = parse(text, mode: 0x43, can: can)
            return got == want ? nil : "parse(\(text.debugDescription)) = \(got), want \(want)"
        }
    }
}

extension String {
    var elmLines: [String] {
        replacingOccurrences(of: "\r", with: "\n").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ">", with: "") }
            .filter { !$0.isEmpty }
    }
}
