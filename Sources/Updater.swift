import Sparkle
import SwiftUI

/// Plugd's own updates, through Sparkle. The feed is appcast.xml on plugd.almoayyad.dev (SUFeedURL in Info.plist).
/// Sparkle checks once a day while "Check for updates" is on and shows its own Install window;
/// the probe at launch also feeds the banner on Home and the menu bar line.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updater()
    /// A newer version from the last check, or nil.
    @Published var latest: String?
    private var controller: SPUStandardUpdaterController!

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// What's new in this version, from CHANGELOG.md in the app. The same file feeds Sparkle's update window (tools/appcast.sh).
    static var currentNotes: [String] {
        let file = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
        return notes(for: current, in: file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
    }

    /// The "- " lines under "## <version>".
    nonisolated static func notes(for version: String, in text: String) -> [String] {
        var inside = false
        var out: [String] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("## ") {
                if inside { break }
                inside = line.dropFirst(3).trimmingCharacters(in: .whitespaces) == version
            } else if inside, line.hasPrefix("- ") {
                out.append(String(line.dropFirst(2)))
            }
        }
        return out
    }

    nonisolated static func notesSelfTest() -> [String] {
        let text = "# What's new\n- not a note\n## 0.3.10\n- ten\n## 0.3.1\n- one a\n- one b\n\n## 0.3.0\n- zero\n"
        var fails: [String] = []
        if notes(for: "0.3.1", in: text) != ["one a", "one b"] { fails.append("notes 0.3.1: \(notes(for: "0.3.1", in: text))") }
        if notes(for: "0.3.10", in: text) != ["ten"] { fails.append("notes 0.3.10") }
        if !notes(for: "9.9", in: text).isEmpty { fails.append("notes for a missing version") }
        return fails
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = Settings.checkUpdates
        if Settings.checkUpdates { controller.updater.checkForUpdateInformation() }
    }

    /// Shows Sparkle's window: Install and Relaunch when there's an update, "up to date" when not.
    func checkNow() { controller.checkForUpdates(nil) }

    func setAutomatic(_ on: Bool) { controller.updater.automaticallyChecksForUpdates = on }

    // PLUGD_FEED points a test copy at a local feed.
    func feedURLString(for updater: SPUUpdater) -> String? { ProcessInfo.processInfo.environment["PLUGD_FEED"] }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { latest = item.displayVersionString }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { latest = nil }
}

/// Shown once after an update, and from the version under the sidebar.
struct WhatsNewSheet: View {
    let notes: [String]
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What's New in Plugd \(Updater.current)").font(.title2.weight(.bold))
            ForEach(notes, id: \.self) { note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.accentColor)
                    Text(note).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Continue", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 460)
    }
}
