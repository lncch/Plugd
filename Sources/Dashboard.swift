import SwiftUI

extension Engine {
    /// Opens the adapter and keeps reading the supported PIDs until stopLive().
    func startLive() {
        guard liveTask == nil, let port, canUseAdapter else { return }
        serialBusy = true
        liveError = nil
        live = [:]
        liveTask = Task {
            // The loop runs off the main thread; pass Stop (cancel) through to it.
            let loop = Task.detached { [self] () -> String? in
                guard let e = ELM.open(port) else { return "The adapter did not answer. Unplug it and plug it back in." }
                defer { e.close() }
                guard let ids = e.supported() else { return "No answer from the car. Turn the ignition on and set the adapter switch to HS." }
                let pids = ELM.pids.filter { ids.contains($0.id) }
                await MainActor.run { self.liveSupported = pids.map(\.id) }
                var misses = 0
                while !Task.isCancelled {
                    var got = false
                    for pid in pids where !Task.isCancelled {
                        guard let v = e.value(of: pid) else { continue }
                        got = true
                        await MainActor.run { self.live[pid.id] = v }
                    }
                    if got { await MainActor.run { self.recordRow() } }
                    // Unplugged or ignition off: stop instead of spinning.
                    misses = got ? 0 : misses + 1
                    if misses >= 3 { return "The car stopped answering." }
                }
                return nil
            }
            let error = await withTaskCancellationHandler { await loop.value } onCancel: { loop.cancel() }
            liveError = error
            liveTask = nil
            serialBusy = false
            stopRecording()   // Stop, an error or opening FORScan all save what was recorded
            if let error { say("Dashboard: \(error)") }
        }
    }

    func stopLive() async {
        guard let task = liveTask else { return }
        task.cancel()
        await task.value
    }

    // MARK: - Recording

    func startRecording() {
        recordRows = []
        recordingSince = Date()
    }

    /// One CSV row after each pass over the readings.
    func recordRow() {
        guard let since = recordingSince, let ids = liveSupported else { return }
        recordRows.append(Self.csvRow(Date().timeIntervalSince(since), ids.map { live[$0] }))
    }

    /// Saves the recording into the files folder and shows it in Finder.
    func stopRecording() {
        guard let since = recordingSince else { return }
        recordingSince = nil
        guard let ids = liveSupported, !recordRows.isEmpty else { return }
        let url = filesDir.appendingPathComponent("Dashboard \(Self.isoFormatter("yyyy-MM-dd HH.mm").string(from: since)).csv")
        do {
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
            try Self.csv(ids, recordRows).write(to: url, atomically: true, encoding: .utf8)
            say("Saved \(recordRows.count) readings to \(url.lastPathComponent)")
            refreshFiles()
            reveal(url)
        } catch {
            notice = "Could not save the recording: \(error.localizedDescription)"
        }
        recordRows = []
    }

    /// A byte order mark first, so Excel reads °C right.
    nonisolated static func csv(_ ids: [UInt8], _ rows: [String]) -> String {
        let names = ids.compactMap { id in ELM.pids.first { $0.id == id }.map { "\($0.name) (\($0.unit))" } }
        return "\u{FEFF}" + ([(["Seconds"] + names).joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }

    nonisolated static func csvRow(_ seconds: Double, _ values: [Double?]) -> String {
        ([String(format: "%.1f", seconds)] + values.map { $0.map { String(format: "%.1f", $0) } ?? "" }).joined(separator: ",")
    }
}

struct DashboardPage: View {
    @EnvironmentObject var engine: Engine
    @State private var stopped = false
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        HStack(spacing: 10) {
            if engine.liveTask != nil {
                Button { stopped = true; Task { await engine.stopLive() } } label: { Label("Stop", systemImage: "stop.fill") }
                if engine.liveSupported == nil {
                    ProgressView().controlSize(.small)
                    Text("Finding the car… up to 15 seconds.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Live").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let since = engine.recordingSince {
                        Text(since, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.red)
                        Button { engine.stopRecording() } label: { Label("Stop Recording", systemImage: "stop.circle") }
                    } else {
                        Button { engine.startRecording() } label: { Label("Record", systemImage: "record.circle") }
                            .help("Saves every reading to a CSV file you can open in Numbers or Excel.")
                    }
                }
            } else {
                Button { stopped = false; engine.startLive() } label: { Label("Start", systemImage: "play.fill") }
                    .disabled(!engine.canUseAdapter)
                Text(hint).font(.caption).foregroundStyle(engine.liveError == nil ? Color.secondary : .orange)
            }
        }
        if let ids = engine.liveSupported {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ELM.pids.filter { ids.contains($0.id) }, id: \.id) { pid in
                    Gauge(pid: pid, value: engine.live[pid.id])
                }
            }
            Text("Only the readings your car reports are shown. Oil life and the odometer need Ford-only requests; they come later.")
                .font(.caption).foregroundStyle(.secondary)
        }
        // Starts by itself once the adapter is free (the window reads its version first). Stop and errors stay stopped.
        Color.clear.frame(height: 0).task(id: engine.canUseAdapter) {
            if engine.canUseAdapter, !stopped, engine.liveError == nil { engine.startLive() }
        }
    }

    private var hint: String {
        if let e = engine.liveError { return e }
        if engine.port == nil { return "Plug in an adapter first." }
        if engine.running { return "FORScan is using the adapter. Quit it to see live data." }
        if engine.portHeld { return "Another program is using the adapter." }
        return "Ignition on, adapter switch on HS. Reads live values about once a second."
    }
}

private struct Gauge: View {
    let pid: ELM.PID
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pid.name).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(pid.format) ?? "–").font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .numberTransition()
                Text(pid.unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension ELM.PID {
    func format(_ v: Double) -> String {
        unit == "V" ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}

private extension View {
    /// Digits roll when a value changes; macOS 12 just swaps them.
    @ViewBuilder func numberTransition() -> some View {
        if #available(macOS 13, *) { contentTransition(.numericText()) } else { self }
    }
}
