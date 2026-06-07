import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section(L("General", "Allgemein")) {
                Toggle(L("Launch at login", "Beim Login starten"), isOn: $settings.launchAtLogin)
                Toggle(L("Show music controls", "Musik-Steuerung anzeigen"), isOn: $settings.showMusicControls)
            }

            Section(L("Claude limit", "Claude-Limit")) {
                Picker(L("Ring shows", "Ring zeigt"), selection: $settings.ringMetric) {
                    ForEach(RingMetric.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("Plan price", "Abo-Preis"))
                        Spacer()
                        Text("$\(Int(settings.planMonthlyPrice)) \(L("/ month", "/ Monat"))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        planButton("Pro", 20)
                        planButton("Max 5×", 100)
                        planButton("Max 20×", 200)
                        Stepper("", value: $settings.planMonthlyPrice, in: 5...500, step: 5)
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("Warning threshold", "Warnschwelle"))
                        Spacer()
                        Text("\(Int(settings.warnThreshold * 100)) %")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.warnThreshold, in: 0.5...1.0, step: 0.05)
                    Text(L("The ring turns to the warning colour above this.",
                           "Ring wird ab hier zur Warnfarbe."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section(L("Appearance", "Aussehen")) {
                HStack(spacing: 12) {
                    Text(L("Accent color", "Akzentfarbe"))
                    Spacer()
                    ForEach(AppSettings.accentChoices, id: \.self) { name in
                        Circle()
                            .fill(AppSettings.color(for: name))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(settings.accent == name ? 0.9 : 0), lineWidth: 2)
                                    .padding(-3)
                            )
                            .contentShape(Circle())
                            .onTapGesture { settings.accent = name }
                    }
                }
            }

            Section {
                HStack {
                    Text("Dynamic Island \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Reset cache", "Cache zurücksetzen")) { resetCache() }
                    Button(L("Quit", "Beenden")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    private func planButton(_ title: String, _ price: Double) -> some View {
        Button(title) { settings.planMonthlyPrice = price }
            .buttonStyle(.bordered)
            .tint(settings.planMonthlyPrice == price ? settings.accentColor : nil)
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(v)"
    }

    private func resetCache() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.julian.dynamicisland/statscache.json")
        if let url { try? FileManager.default.removeItem(at: url) }
        NotificationCenter.default.post(name: .diSettingsChanged, object: nil)
    }
}

/// Lightweight controller that shows the settings window from an accessory app.
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = L("Dynamic Island – Settings", "Dynamic Island – Einstellungen")
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
