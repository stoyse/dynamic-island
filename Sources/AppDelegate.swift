import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let spotify = SpotifyMonitor()
    let usage = ClaudeUsageMonitor()
    let stats = ClaudeStatsMonitor()
    let updater = UpdateChecker()
    var controller: NotchController?
    lazy var settingsWindow = SettingsWindowController(updater: updater)
    lazy var onboarding = OnboardingWindowController(usage: usage)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no menu bar app
        spotify.start()
        usage.start()
        stats.start()
        updater.start()
        controller = NotchController(spotify: spotify, usage: usage, stats: stats, updater: updater)

        // First launch → show the setup screen.
        if ProcessInfo.processInfo.environment["DI_DEBUG"] == "1" {
            FileHandle.standardError.write("DI_ONBOARD hasOnboarded=\(AppSettings.shared.hasOnboarded) lang=\(Locale.preferredLanguages.first ?? "?")\n".data(using: .utf8)!)
        }
        if !AppSettings.shared.hasOnboarded {
            onboarding.show()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(openSettings),
            name: .diOpenSettings, object: nil)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func screensChanged() {
        // Debounce a touch — screen params can fire several times.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(doReposition), object: nil)
        perform(#selector(doReposition), with: nil, afterDelay: 0.3)
    }

    @objc private func doReposition() {
        controller?.reposition()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
