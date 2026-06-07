import AppKit

/// What is currently playing on Spotify or in a browser (YouTube).
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var source: String          // "Spotify", "YouTube", ...
    var artwork: NSImage?
    var duration: Double        // seconds (0 if unknown)
    var position: Double        // seconds (0 if unknown)

    static func == (l: NowPlaying, r: NowPlaying) -> Bool {
        l.title == r.title && l.artist == r.artist && l.isPlaying == r.isPlaying &&
        l.source == r.source && l.duration == r.duration &&
        // compare artwork by identity/size to avoid expensive pixel diff
        (l.artwork === r.artwork)
    }
}

/// Real usage straight from Anthropic's OAuth usage endpoint — the exact numbers
/// shown in Claude's settings (`/api/oauth/usage`). Utilizations are 0...1 fractions.
struct UsageInfo: Equatable {
    var fiveHourPercent: Double     // 5-hour session limit
    var fiveHourReset: Date?
    var sevenDayPercent: Double     // weekly (7-day) limit
    var sevenDayReset: Date?
    var opusPercent: Double?        // weekly Opus limit (Max plans), nil if not applicable
    var opusReset: Date?
    var valid: Bool                 // true once a real response has been parsed
    var statusNote: String?         // transient state: rate-limited / offline / token issue

    /// The headline number for the ring = the 5-hour session usage.
    var percent: Double { fiveHourPercent }

    static let empty = UsageInfo(fiveHourPercent: 0, fiveHourReset: nil,
                                 sevenDayPercent: 0, sevenDayReset: nil,
                                 opusPercent: nil, opusReset: nil,
                                 valid: false, statusNote: nil)
}

/// One day's aggregated Claude usage (for the history sparkline).
struct DailyUsage: Equatable, Identifiable {
    var id: String { day }
    var day: String      // "yyyy-MM-dd"
    var label: String    // short label e.g. "Mo" or "01.06"
    var tokens: Int      // total raw tokens that day
    var cost: Double     // estimated API-equivalent USD that day
}

/// Lifetime / historical Claude usage computed from local JSONL transcripts.
/// (The Anthropic endpoint only gives % utilization — totals come from here.)
struct ClaudeStats: Equatable {
    var totalTokens: Int          // lifetime raw tokens
    var totalCost: Double         // lifetime estimated API-equivalent USD
    var monthTokens: Int          // current calendar month
    var monthCost: Double         // current month estimated USD
    var todayTokens: Int
    var last14Days: [DailyUsage]  // chronological, most recent last
    var planMonthlyPrice: Double  // assumed subscription price (USD/month)
    var recommendation: String    // human-readable verdict
    var valid: Bool

    static let empty = ClaudeStats(totalTokens: 0, totalCost: 0, monthTokens: 0,
                                   monthCost: 0, todayTokens: 0, last14Days: [],
                                   planMonthlyPrice: 100, recommendation: "…", valid: false)
}
