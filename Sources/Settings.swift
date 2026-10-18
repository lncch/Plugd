import ServiceManagement
import SwiftUI

/// Settings stored in UserDefaults. Read here for code outside SwiftUI views.
enum Settings {
    /// A setting that was never changed reads as on (the default for all of these).
    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) }
    static var showMenuBar: Bool { on("showMenuBar") }
    static var showDock: Bool { on("showDock") || !showMenuBar }   // never hide both, or Plugd can't be reached
    static var checkUpdates: Bool { on("checkUpdates") }

    static func applyDock() {
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }
}

struct SettingsPage: View {
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("showDock") private var showDock = true
    @AppStorage("checkUpdates") private var checkUpdates = true
    @AppStorage("seenWelcome") private var seenWelcome = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Open at login", "Plugd starts in the menu bar when you log in, without opening its window.", isOn: Binding(
                get: { openAtLogin },
                set: { setOpenAtLogin($0) }))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.orange).padding(.bottom, 10)
            }
            Divider()
            row("Show in menu bar", "Adapter status, Open FORScan and engine codes from the menu bar. Closing the window keeps Plugd running there.", isOn: $showMenuBar)
            Divider()
            row("Show in Dock", showMenuBar ? "Turn off to keep Plugd only in the menu bar." : "Needed while the menu bar icon is off, so you can reach Plugd.", isOn: $showDock)
                .disabled(!showMenuBar)
            Divider()
            row("Check for FORScan updates", "Looks at forscan.org when Plugd starts and tells you when a new version is out.", isOn: $checkUpdates)
        }
        .padding(.horizontal, 16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: showMenuBar) {
            if !showMenuBar { showDock = true }
            Settings.applyDock()
        }
        .onChange(of: showDock) {
            Settings.applyDock()
            // Leaving the Dock moves the window behind other apps; bring it back.
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Show the Welcome Again") { seenWelcome = false }
    }

    private func row(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 12)
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS said no: \(error.localizedDescription). Move Plugd to Applications and try again."
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}
