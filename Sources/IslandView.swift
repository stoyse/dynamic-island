import SwiftUI
import AppKit

/// A rect with squared top corners (flush to the bezel) and rounded bottom corners.
struct IslandShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.height / 2, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var spotify: SpotifyMonitor
    @ObservedObject var usage: ClaudeUsageMonitor
    @ObservedObject var stats: ClaudeStatsMonitor
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var state: IslandState
    let geo: NotchGeometry

    @ObservedObject var settings = AppSettings.shared

    /// The history bar the user tapped in the Claude detail view (nil = show summary).
    @State private var selectedDay: DailyUsage?
    @State private var updatePulse = false

    // Seek-bar playback clock. The monitor polls position only every ~1.5s, so we
    // sample it and extrapolate locally for smooth movement between polls.
    @State private var sampledPos: Double = 0
    @State private var sampledAt: Date = Date(timeIntervalSince1970: 0)
    @State private var scrubbing = false
    @State private var scrubFraction: Double = 0

    private var islandW: CGFloat { state.expanded ? geo.expandedWidth : geo.collapsedWidth }
    private var islandH: CGFloat { (state.expanded ? geo.height(for: state.mode) : geo.collapsedHeight) + bannerExtra }
    private var sideArm: CGFloat { (geo.collapsedWidth - geo.notchWidth) / 2 }

    /// Extra height the expanded island gains for the update banner.
    private var bannerExtra: CGFloat {
        (state.expanded && updater.available != nil) ? NotchGeometry.updateBannerHeight : 0
    }
    private var accent: Color { settings.accentColor }

    var body: some View {
        ZStack(alignment: .top) {
            IslandShape(radius: state.expanded ? 26 : 11)
                .fill(Color.black)
                .overlay(
                    IslandShape(radius: state.expanded ? 26 : 11)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .frame(width: islandW, height: islandH)
                .shadow(color: .black.opacity(0.4), radius: 9, y: 5)

            Group {
                if !state.expanded {
                    collapsedContent
                } else if state.mode == .music {
                    musicDetail
                } else {
                    claudeDetail
                }
            }
            .transition(.opacity)
        }
        .overlay(alignment: .topTrailing) {
            if state.expanded {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
                    .onTapGesture { NotificationCenter.default.post(name: .diOpenSettings, object: nil) }
                    .padding(.top, 7)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: state.expanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: updater.available)
        .foregroundStyle(.white)
        .onChange(of: state.expanded) { open in if !open { selectedDay = nil } }
        .onChange(of: state.mode) { m in if m != .claude { selectedDay = nil } }
    }

    // MARK: Collapsed (around the notch)

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            HStack { Spacer(); artwork(size: geo.notchHeight - 14) }
                .frame(width: sideArm)
                .padding(.trailing, 9)
            Color.clear.frame(width: geo.notchWidth)
            HStack {
                usageRing(size: geo.notchHeight - 14, lineWidth: 3, showLabel: false)
                    .overlay(alignment: .topTrailing) {
                        if updater.available != nil { collapsedUpdateBadge }
                    }
                Spacer()
            }
            .frame(width: sideArm)
            .padding(.leading, 9)
        }
        .frame(width: geo.collapsedWidth, height: geo.notchHeight)
    }

    /// Tiny pulsing badge shown on the collapsed ring when an update is available.
    private var collapsedUpdateBadge: some View {
        Circle()
            .fill(accent)
            .frame(width: 9, height: 9)
            .overlay(Image(systemName: "arrow.down")
                .font(.system(size: 5.5, weight: .black)).foregroundStyle(.black))
            .scaleEffect(updatePulse ? 1.18 : 0.9)
            .opacity(updatePulse ? 1 : 0.65)
            .offset(x: 2, y: -2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { updatePulse = true }
            }
    }

    // MARK: Expanded — Music

    private var musicDetail: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geo.notchHeight)   // keep the physical notch clear
            updateBanner
            HStack(spacing: 12) {
                HStack(spacing: 11) {
                    artwork(size: 48)
                        .contentShape(RoundedRectangle(cornerRadius: 48 * 0.24, style: .continuous))
                        .onTapGesture { spotify.revealInApp(source: spotify.nowPlaying?.source) }
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spotify.nowPlaying?.title ?? L("Nothing playing", "Nichts läuft"))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                sourceGlyph(size: 12)
                                Text(sourceLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { spotify.revealInApp(source: spotify.nowPlaying?.source) }
                        if settings.showMusicControls && spotify.nowPlaying?.source == "Spotify" {
                            controlsRow
                            waveformSeekBar
                        } else {
                            progressBar.padding(.top, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 56)

                claudeSummary
                    .frame(width: 158)
                    .contentShape(Rectangle())
                    .onTapGesture { state.mode = .claude }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(width: geo.expandedWidth, height: geo.musicHeight + bannerExtra)
    }

    // MARK: Update banner (expanded)

    @ViewBuilder private var updateBanner: some View {
        if let info = updater.available {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Update available", "Update verfügbar"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(bannerSubtitle(info))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                bannerAction(info)
            }
            .padding(.horizontal, 16)
            .frame(height: NotchGeometry.updateBannerHeight)
            .background(
                LinearGradient(colors: [accent.opacity(0.20), accent.opacity(0.06)],
                               startPoint: .leading, endPoint: .trailing))
            .overlay(Rectangle().fill(.white.opacity(0.07)).frame(height: 1), alignment: .bottom)
        }
    }

    private func bannerSubtitle(_ info: UpdateInfo) -> String {
        switch updater.state {
        case .idle:               return "v\(info.version) · " + L("one click to update", "ein Klick zum Aktualisieren")
        case .downloading(let p): return L("Downloading…", "Lädt…") + " \(Int(p * 100))%"
        case .installing:         return L("Installing… the app will restart", "Installiere… die App startet neu")
        case .failed(let m):      return m
        }
    }

    @ViewBuilder private func bannerAction(_ info: UpdateInfo) -> some View {
        switch updater.state {
        case .downloading(let p):
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(width: 90, height: 6)
                Capsule().fill(accent).frame(width: max(6, 90 * CGFloat(p)), height: 6)
            }
        case .installing:
            ProgressView().controlSize(.small)
        default:
            Button(action: { updater.installUpdate() }) {
                Text(isFailedState ? L("Retry", "Erneut") : L("Update now", "Jetzt aktualisieren"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent))
                    .shadow(color: accent.opacity(0.5), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    private var isFailedState: Bool {
        if case .failed = updater.state { return true } else { return false }
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            controlButton("backward.fill", size: 12) { spotify.previousTrack() }
            controlButton(spotify.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill", size: 14) { spotify.playPause() }
            controlButton("forward.fill", size: 12) { spotify.nextTrack() }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// A Spotify-style scrub bar drawn as a dotted sound wave. Tap or drag anywhere
    /// to seek; the fill extrapolates locally so it glides between the 1.5s polls.
    @ViewBuilder private var waveformSeekBar: some View {
        if let np = spotify.nowPlaying, np.duration > 1 {
            TimelineView(.periodic(from: .now, by: 0.08)) { ctx in
                let elapsed = np.isPlaying ? max(0, ctx.date.timeIntervalSince(sampledAt)) : 0
                let livePos = min(np.duration, sampledPos + elapsed)
                let frac = scrubbing ? scrubFraction : livePos / np.duration
                let shown = scrubbing ? scrubFraction * np.duration : livePos
                VStack(spacing: 4) {
                    DottedWaveformSeekBar(
                        progress: min(1, max(0, frac)),
                        onScrub: { f in
                            scrubbing = true
                            scrubFraction = f
                        },
                        onCommit: { f in
                            let target = f * np.duration
                            sampledPos = target
                            sampledAt = Date()
                            scrubbing = false
                            spotify.seek(to: target)
                        }
                    )
                    .frame(height: 22)
                    HStack {
                        Text(timeStr(shown))
                        Spacer()
                        Text(timeStr(np.duration))
                    }
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(scrubbing ? 0.7 : 0.4))
                }
            }
            .frame(height: 34)
            .padding(.top, 4)
            // Re-sample the playback clock whenever the monitor republishes.
            .onChange(of: spotify.nowPlaying?.position) { newPos in
                if !scrubbing {
                    sampledPos = newPos ?? 0
                    sampledAt = Date()
                }
            }
            .onChange(of: spotify.nowPlaying?.title) { _ in
                scrubbing = false
                sampledPos = spotify.nowPlaying?.position ?? 0
                sampledAt = Date()
            }
        }
    }

    private func timeStr(_ s: Double) -> String {
        let t = Int(max(0, s.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func controlButton(_ symbol: String, size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 24, height: 20)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    @ViewBuilder private var progressBar: some View {
        if let np = spotify.nowPlaying, np.duration > 1 {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: max(2, g.size.width * CGFloat(min(1, np.position / np.duration))))
                }
            }
            .frame(height: 3)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "waveform").font(.system(size: 8))
                Text(spotify.nowPlaying?.source ?? "").font(.system(size: 9))
            }
            .foregroundStyle(.white.opacity(0.45))
            .frame(height: 12, alignment: .leading)
        }
    }

    private var claudeSummary: some View {
        HStack(spacing: 10) {
            usageRing(size: 44, lineWidth: 5, showLabel: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text("Claude · \(ringTitle)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text("\(pct(ringPercent))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(usageColor)
                Text(resetText(ringReset))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                Text(secondaryUsageText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Expanded — Claude detail

    private var claudeDetail: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geo.notchHeight)
            updateBanner
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    backButton
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDay != nil ? "\(L("Day", "Tag")) \(selectedDay!.label)" : L("Claude Code · Stats", "Claude Code · Statistik"))
                            .font(.system(size: 12.5, weight: .semibold))
                        if let d = selectedDay {
                            Text("\(bigTokens(d.tokens)) Tokens · \(money(d.cost)) \(L("API value", "API-Wert"))")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.green.opacity(0.9))
                        } else {
                            Text(stats.stats.valid ? stats.stats.recommendation : L("Calculating stats …", "Statistik wird berechnet …"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 6)
                    usageRing(size: 40, lineWidth: 4, showLabel: true)
                }

                HStack(spacing: 0) {
                    metric(bigTokens(stats.stats.totalTokens), L("Total tokens", "Tokens gesamt"))
                    metricDivider
                    metric("$\(Int(stats.stats.totalCost))", L("Total API value", "API-Wert gesamt"))
                    metricDivider
                    metric("$\(Int(stats.stats.monthCost))", L("Value / month", "Wert / Monat"))
                    metricDivider
                    metric("$\(Int(stats.stats.planMonthlyPrice))", L("Plan / month", "Abo / Monat"))
                }

                historyBars
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: geo.expandedWidth, height: geo.claudeHeight + bannerExtra)
    }

    private var backButton: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.white.opacity(0.1)))
            .contentShape(Circle())
            .onTapGesture { state.mode = .music }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .bold))
            Text(label).font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
    }

    private var historyBars: some View {
        let days = stats.stats.last14Days
        let maxTok = max(1, days.map { $0.tokens }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { d in
                let isSelected = selectedDay?.id == d.id
                let isToday = d.id == days.last?.id
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isSelected ? Color.green
                              : (isToday ? Color.green.opacity(0.55) : Color.white.opacity(0.32)))
                        .frame(height: max(2, 30 * CGFloat(d.tokens) / CGFloat(maxTok)))
                        .overlay(alignment: .top) {
                            if isSelected {
                                Circle().fill(Color.green).frame(width: 4, height: 4).offset(y: -6)
                            }
                        }
                    Text(String(d.label.prefix(2)))
                        .font(.system(size: 7, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedDay = isSelected ? nil : d
                    }
                }
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    // MARK: Reusable pieces

    /// "Spotify · Artist" (or just the source when no artist / nothing playing).
    private var sourceLabel: String {
        guard let np = spotify.nowPlaying else { return "Spotify · YouTube" }
        return np.artist.isEmpty ? np.source : "\(np.source) · \(np.artist)"
    }

    /// A tiny brand-coloured glyph for the current source (Spotify / YouTube / other).
    @ViewBuilder private func sourceGlyph(size: CGFloat) -> some View {
        switch spotify.nowPlaying?.source {
        case "Spotify":
            ZStack {
                Circle().fill(Color(red: 0.11, green: 0.84, blue: 0.38))
                SpotifyArcs()
                    .stroke(Color.black.opacity(0.85),
                            style: StrokeStyle(lineWidth: max(1, size * 0.10), lineCap: .round))
                    .padding(size * 0.20)
            }
            .frame(width: size, height: size)
        case "YouTube":
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Color.red)
                Image(systemName: "play.fill").font(.system(size: size * 0.5)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        default:
            Image(systemName: "music.note")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder private func artwork(size: CGFloat) -> some View {
        if let img = spotify.nowPlaying?.artwork {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }

    // The value the ring represents depends on the chosen metric in settings.
    private var ringPercent: Double {
        switch settings.ringMetric {
        case .fiveHour: return usage.usage.fiveHourPercent
        case .week:     return usage.usage.sevenDayPercent
        case .opus:     return usage.usage.opusPercent ?? usage.usage.sevenDayPercent
        }
    }
    private var ringReset: Date? {
        switch settings.ringMetric {
        case .fiveHour: return usage.usage.fiveHourReset
        case .week:     return usage.usage.sevenDayReset
        case .opus:     return usage.usage.opusReset ?? usage.usage.sevenDayReset
        }
    }
    private var ringTitle: String { settings.ringMetric.short }

    /// A complementary metric shown under the headline number.
    private var secondaryUsageText: String {
        settings.ringMetric == .week
            ? "5h \(pct(usage.usage.fiveHourPercent))%"
            : "\(L("Week", "Woche")) \(pct(usage.usage.sevenDayPercent))%"
    }

    private func usageRing(size: CGFloat, lineWidth: CGFloat, showLabel: Bool) -> some View {
        let p = max(0, min(1, ringPercent))
        return ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(p))
                .stroke(usageColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showLabel {
                Text("\(pct(ringPercent))")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.5), value: p)
    }

    private var usageColor: Color {
        let p = ringPercent
        if p < settings.warnThreshold { return settings.accentColor }
        if p < 1.0 { return .orange }
        return .red
    }

    private func pct(_ x: Double) -> Int { Int((max(0, x) * 100).rounded()) }

    private func resetText(_ date: Date?, prefix: Bool = true) -> String {
        guard let date else { return prefix ? L("no active limit", "kein aktives Limit") : "—" }
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return prefix ? L("reset", "zurückgesetzt") : "0m" }
        let h = Int(secs) / 3600, m = (Int(secs) % 3600) / 60, d = Int(secs) / 86400
        let body = d > 0 ? "\(d)d \(h % 24)h" : (h > 0 ? "\(h)h \(m)m" : "\(m)m")
        return prefix ? "Reset in \(body)" : body
    }

    private func money(_ v: Double) -> String {
        v >= 10 ? "$\(Int(v.rounded()))" : String(format: "$%.1f", v)
    }

    private func bigTokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000 { return String(format: "%.1fB", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0fk", d / 1_000) }
        return "\(n)"
    }
}

/// The three stacked, upward-bulging arcs of the Spotify mark.
struct SpotifyArcs: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let arcs: [(y: CGFloat, inset: CGFloat)] = [(0.30, 0.04), (0.52, 0.16), (0.74, 0.28)]
        for a in arcs {
            let y = rect.minY + h * a.y
            let x0 = rect.minX + w * a.inset
            let x1 = rect.maxX - w * a.inset
            p.move(to: CGPoint(x: x0, y: y))
            p.addQuadCurve(to: CGPoint(x: x1, y: y),
                           control: CGPoint(x: rect.midX, y: y - h * 0.16))
        }
        return p
    }
}

/// A seek bar rendered as a dotted sound wave. Each column is a vertical stack of
/// dots whose count follows a stable pseudo-organic amplitude; columns left of the
/// playhead are bright, the rest dim. Tap or drag to seek.
struct DottedWaveformSeekBar: View {
    var progress: Double                  // 0...1, visual fill
    var onScrub: (Double) -> Void         // continuous while dragging
    var onCommit: (Double) -> Void        // on release → perform the seek

    private let columnPitch: CGFloat = 4.2    // horizontal spacing per column
    private let dotSize: CGFloat = 2.0        // dot diameter
    private let dotPitch: CGFloat = 2.9       // vertical spacing per dot

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let count = max(8, Int(w / columnPitch))
            let maxDots = max(2, Int(h / dotPitch))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    let amp = Self.amplitude(i)
                    let dots = max(1, Int((amp * CGFloat(maxDots)).rounded()))
                    let played = (Double(i) + 0.5) / Double(count) <= progress
                    VStack(spacing: dotPitch - dotSize) {
                        ForEach(0..<dots, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(played ? 0.95 : 0.32))
                                .frame(width: dotSize, height: dotSize)
                        }
                    }
                    .frame(width: columnPitch, height: h, alignment: .center)
                }
            }
            .frame(width: w, height: h, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in onScrub(min(1, max(0, v.location.x / w))) }
                    .onEnded   { v in onCommit(min(1, max(0, v.location.x / w))) }
            )
        }
    }

    /// Stable, organic-looking amplitude (0.18...1) for column `i` — a few summed
    /// sines plus a hashed jitter, so the wave is the same on every redraw.
    static func amplitude(_ i: Int) -> CGFloat {
        let x = Double(i)
        let s = sin(x * 0.50) * 0.50 + sin(x * 1.27 + 1.0) * 0.30 + sin(x * 0.21 + 2.3) * 0.20
        let n = Double((i &* 2654435761 >> 8) % 100) / 100.0
        let v = (s * 0.5 + 0.5) * 0.72 + n * 0.28
        return CGFloat(min(1, max(0.18, v)))
    }
}
