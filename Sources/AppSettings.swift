import SwiftUI
import Foundation

extension Notification.Name {
    static let diOpenSettings = Notification.Name("di.openSettings")
    static let diSettingsChanged = Notification.Name("di.settingsChanged")
}

/// Which usage value the ring shows.
enum RingMetric: String, CaseIterable, Identifiable {
    case fiveHour, week, opus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fiveHour: return L("5 hours", "5 Stunden")
        case .week:     return L("Week", "Woche")
        case .opus:     return "Opus"
        }
    }
    var short: String {
        switch self {
        case .fiveHour: return "5h"
        case .week:     return L("Week", "Woche")
        case .opus:     return "Opus"
        }
    }
}

/// Central, UserDefaults-backed settings shared by the island + settings window.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard
    private var loading = true

    @Published var launchAtLogin: Bool { didSet { persistAndApply() { self.applyLaunchAtLogin() } } }
    @Published var planMonthlyPrice: Double { didSet { persistAndApply() { self.d.set(self.planMonthlyPrice, forKey: "planMonthlyPrice"); self.broadcast() } } }
    @Published var ringMetric: RingMetric { didSet { persistAndApply() { self.d.set(self.ringMetric.rawValue, forKey: "ringMetric") } } }
    @Published var warnThreshold: Double { didSet { persistAndApply() { self.d.set(self.warnThreshold, forKey: "warnThreshold") } } }
    @Published var accent: String { didSet { persistAndApply() { self.d.set(self.accent, forKey: "accent") } } }
    @Published var showMusicControls: Bool { didSet { persistAndApply() { self.d.set(self.showMusicControls, forKey: "showMusicControls") } } }

    private init() {
        planMonthlyPrice = (d.object(forKey: "planMonthlyPrice") as? Double) ?? 100
        ringMetric = RingMetric(rawValue: d.string(forKey: "ringMetric") ?? "") ?? .fiveHour
        warnThreshold = (d.object(forKey: "warnThreshold") as? Double) ?? 0.8
        accent = d.string(forKey: "accent") ?? "green"
        showMusicControls = (d.object(forKey: "showMusicControls") as? Bool) ?? true
        launchAtLogin = FileManager.default.fileExists(atPath: Self.launchAgentPath)
        loading = false
    }

    /// Run a side effect only for real user changes (not during init).
    private func persistAndApply(_ work: () -> Void) {
        guard !loading else { return }
        work()
    }

    private func broadcast() {
        NotificationCenter.default.post(name: .diSettingsChanged, object: nil)
    }

    // MARK: Accent color

    var accentColor: Color {
        switch accent {
        case "blue":   return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "pink":   return .pink
        default:       return .green
        }
    }
    static let accentChoices = ["green", "blue", "purple", "orange", "pink"]
    static func color(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return .pink
        default: return .green
        }
    }

    // MARK: Launch at login (LaunchAgent)

    private static let label = "com.julian.dynamicisland"
    private static var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    private func applyLaunchAtLogin() {
        let fm = FileManager.default
        let path = Self.launchAgentPath
        if launchAtLogin {
            let bin = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>Label</key><string>\(Self.label)</string>
            <key>ProgramArguments</key><array><string>\(bin)</string></array>
            <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
            <key>ProcessType</key><string>Interactive</string>
            <key>LimitLoadToSessionType</key><string>Aqua</string>
            </dict></plist>
            """
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
            try? plist.write(toFile: path, atomically: true, encoding: .utf8)
            launchctl(["enable", "gui/\(getuid())/\(Self.label)"])
            launchctl(["bootstrap", "gui/\(getuid())", path])
        } else {
            // Just remove the autostart entry; the running instance keeps going.
            try? fm.removeItem(atPath: path)
            launchctl(["disable", "gui/\(getuid())/\(Self.label)"])
        }
    }

    @discardableResult
    private func launchctl(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}
