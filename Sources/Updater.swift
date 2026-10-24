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
