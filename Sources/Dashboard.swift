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
            if let error { say("Dashboard: \(error)") }
        }
    }

    func stopLive() async {
        guard let task = liveTask else { return }
        task.cancel()
        await task.value
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
                Text(value.map(format) ?? "–").font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(pid.unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func format(_ v: Double) -> String {
        pid.unit == "V" ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}
