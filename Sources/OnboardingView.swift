import SwiftUI
import AppKit

// MARK: - Plan model

/// One Claude subscription tier shown on the plan step.
private struct ClaudePlan: Identifiable {
    let id = UUID()
    let name: String
    let priceLabel: String
    let blurb: String
    let symbol: String
    let monthly: Double
    let tint: Color

    static let all: [ClaudePlan] = [
        ClaudePlan(name: "Free",    priceLabel: L("Free", "Gratis"),     blurb: L("Casual use",       "Gelegentlich"),      symbol: "sparkles",  monthly: 0,   tint: .gray),
        ClaudePlan(name: "Pro",     priceLabel: "$20",                   blurb: L("Daily driver",     "Täglich"),           symbol: "bolt.fill", monthly: 20,  tint: .blue),
        ClaudePlan(name: "Max 5×",  priceLabel: "$100",                  blurb: L("Power user",       "Power-User"),        symbol: "star.fill", monthly: 100, tint: .purple),
        ClaudePlan(name: "Max 20×", priceLabel: "$200",                  blurb: L("All day, heavy",   "Den ganzen Tag"),    symbol: "crown.fill",monthly: 200, tint: .orange),
    ]
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var settings = AppSettings.shared
    var onFinish: () -> Void

    @State private var step = 0
    @State private var selectedPlan: Double? = nil

    private let stepCount = 4
    private var accent: Color { settings.accentColor }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                progress
                    .padding(.top, 30)
                    .padding(.horizontal, 40)

                ZStack {
                    switch step {
                    case 0: welcomeStep
                    case 1: planStep
                    case 2: ringStep
                    default: finishStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 44)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)

                footer
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 800, height: 580)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .preferredColorScheme(.dark)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.03)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.22), .clear],
                           center: .top, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [accent.opacity(0.10), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: Progress

    private var progress: some View {
        HStack(spacing: 7) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? accent : Color.white.opacity(0.14))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Capsule().fill(.white.opacity(i == step ? 0.0 : 0.0))
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: Step 1 — Welcome

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            IslandPreview(accent: accent)
                .frame(width: 420, height: 92)
                .shadow(color: .black.opacity(0.5), radius: 22, y: 12)

            VStack(spacing: 8) {
                Text(L("Welcome to", "Willkommen bei"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(2)
                Text("Dynamic Island")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .white.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom))
                Text(L("Your notch, reimagined — live music and real-time Claude usage.",
                       "Deine Notch, neu gedacht — Live-Musik und Echtzeit-Claude-Nutzung."))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                feature("waveform", L("Live music", "Live-Musik"),
                        L("Drag the dotted wave to seek", "Welle ziehen zum Spulen"))
                feature("gauge.medium", L("Claude usage", "Claude-Nutzung"),
                        L("Real 5h, weekly & Opus limits", "Echte 5h-, Wochen- & Opus-Limits"))
                feature("menubar.rectangle", L("On the notch", "Auf der Notch"),
                        L("No dock, no menu-bar icon", "Kein Dock, kein Menüleisten-Icon"))
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.14)))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Step 2 — Plan

    private var planStep: some View {
        VStack(spacing: 0) {
            stepHeader("creditcard.fill",
                       L("Which Claude plan are you on?", "Welches Claude-Abo hast du?"),
                       L("So the island can show how much value you're getting.",
                         "Damit die Island zeigt, wie viel Wert du rausholst."))
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                ForEach(ClaudePlan.all) { plan in
                    planCard(plan)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func planCard(_ plan: ClaudePlan) -> some View {
        let isSelected = selectedPlan == plan.monthly
        return VStack(spacing: 12) {
            Image(systemName: plan.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? .white : plan.tint)
                .frame(width: 52, height: 52)
                .background(Circle().fill(isSelected ? plan.tint : plan.tint.opacity(0.16)))

            VStack(spacing: 3) {
                Text(plan.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(plan.priceLabel + (plan.monthly > 0 ? L("/mo", "/Mon") : ""))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(plan.blurb)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? plan.tint : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .shadow(color: isSelected ? plan.tint.opacity(0.35) : .clear, radius: 14, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPlan = plan.monthly
            }
            settings.planMonthlyPrice = plan.monthly
            // Sensible default: Max tiers care about the Opus weekly limit.
            settings.ringMetric = plan.monthly >= 100 ? .opus : .fiveHour
        }
    }

    // MARK: Step 3 — Ring metric

    private var ringStep: some View {
        VStack(spacing: 0) {
            stepHeader("circle.dashed",
                       L("What should the ring track?", "Was soll der Ring anzeigen?"),
                       L("The headline number around the right of your notch.",
                         "Die Hauptzahl rechts an deiner Notch."))
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                ringOption(.fiveHour, "timer",
                           L("5-hour session", "5-Stunden-Sitzung"),
                           L("Your rolling 5-hour limit — resets through the day.",
                             "Dein rollendes 5-Stunden-Limit — setzt sich tagsüber zurück."))
                ringOption(.week, "calendar",
                           L("Weekly", "Wöchentlich"),
                           L("Your 7-day usage limit.", "Dein 7-Tage-Limit."))
                ringOption(.opus, "brain.head.profile",
                           L("Opus weekly", "Opus wöchentlich"),
                           L("The weekly Opus limit on Max plans.",
                             "Das wöchentliche Opus-Limit bei Max-Abos."))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func ringOption(_ metric: RingMetric, _ symbol: String, _ title: String, _ subtitle: String) -> some View {
        let isSelected = settings.ringMetric == metric
        return HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSelected ? .white : accent)
                .frame(width: 46, height: 46)
                .background(Circle().fill(isSelected ? accent : accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? accent : .white.opacity(0.2))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.white.opacity(isSelected ? 0.09 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(isSelected ? accent : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { settings.ringMetric = metric }
        }
    }

    // MARK: Step 4 — Finish

    private var finishStep: some View {
        VStack(spacing: 0) {
            stepHeader("paintpalette.fill",
                       L("Make it yours", "Mach's zu deinem"),
                       L("Pick an accent and decide if it should start with your Mac.",
                         "Wähle eine Akzentfarbe und ob es beim Login startet."))
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Accent color", "Akzentfarbe"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 16) {
                        ForEach(AppSettings.accentChoices, id: \.self) { name in
                            let c = AppSettings.color(for: name)
                            Circle()
                                .fill(c)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: settings.accent == name ? 3 : 0).padding(-4))
                                .shadow(color: settings.accent == name ? c.opacity(0.6) : .clear, radius: 8)
                                .contentShape(Circle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { settings.accent = name }
                                }
                        }
                        Spacer()
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))

                Toggle(isOn: $settings.launchAtLogin) {
                    HStack(spacing: 12) {
                        Image(systemName: "power")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(accent.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Launch at login", "Beim Login starten"))
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Text(L("Always there when your Mac wakes up.", "Immer da, wenn dein Mac startet."))
                                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    // MARK: Shared pieces

    private func stepHeader(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 54, height: 54)
                .background(Circle().fill(accent.opacity(0.14)))
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button(action: { step -= 1 }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(L("Back", "Zurück"))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button(action: advance) {
                HStack(spacing: 6) {
                    Text(step == stepCount - 1
                         ? L("Start using Dynamic Island", "Los geht's")
                         : L("Continue", "Weiter"))
                    Image(systemName: step == stepCount - 1 ? "checkmark" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(canAdvance ? accent : Color.white.opacity(0.12))
                )
                .shadow(color: canAdvance ? accent.opacity(0.45) : .clear, radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
    }

    private var canAdvance: Bool {
        step != 1 || selectedPlan != nil   // plan step requires a selection
    }

    private func advance() {
        if step < stepCount - 1 {
            step += 1
        } else {
            settings.hasOnboarded = true
            onFinish()
        }
    }
}

// MARK: - A small live-looking island preview used as the welcome hero.

private struct IslandPreview: View {
    let accent: Color

    var body: some View {
        IslandShape(radius: 24)
            .fill(Color.black)
            .overlay(IslandShape(radius: 24).stroke(.white.opacity(0.08), lineWidth: 0.5))
            .overlay(content.padding(.horizontal, 18))
    }

    private var content: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.8), accent.opacity(0.4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "music.note").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.85)).frame(width: 110, height: 7)
                miniWave
            }

            Spacer()

            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 4).frame(width: 40, height: 40)
                Circle().trim(from: 0, to: 0.78)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 40, height: 40)
                Text("78").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    private var miniWave: some View {
        HStack(spacing: 2) {
            ForEach(0..<34, id: \.self) { i in
                let amp = DottedWaveformSeekBar.amplitude(i)
                let dots = max(1, Int((amp * 5).rounded()))
                let played = Double(i) / 34 < 0.42
                VStack(spacing: 1) {
                    ForEach(0..<dots, id: \.self) { _ in
                        Circle()
                            .fill(.white.opacity(played ? 0.9 : 0.28))
                            .frame(width: 1.6, height: 1.6)
                    }
                }
                .frame(height: 16)
            }
        }
    }
}

// MARK: - Window controller

/// Shows the first-run onboarding as a borderless, dark, centered window.
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = .black
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            // No dock icon → keep the first-run window reliably reachable on top.
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true

            let root = OnboardingView { [weak self] in self?.close() }
            w.contentView = NSHostingView(rootView: root)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
    }
}
