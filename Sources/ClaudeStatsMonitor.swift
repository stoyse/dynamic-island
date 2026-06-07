import Foundation
import Combine

/// Aggregates Claude usage statistics from local JSONL transcript files.
///
/// Scans `~/.claude/projects/<project-dir>/*.jsonl`, sums raw tokens and
/// estimates API-equivalent cost per message, buckets everything by local
/// calendar day, and publishes a `ClaudeStats` snapshot. Heavy IO/CPU work
/// happens on a background queue; `@Published` updates hop to the main thread.
final class ClaudeStatsMonitor: ObservableObject, @unchecked Sendable {

    // MARK: Published state

    @Published private(set) var stats: ClaudeStats = .empty

    // MARK: Configuration

    /// Default monthly price assumption (Claude Max 5x) when no override is set.
    private static let defaultPlanMonthlyPrice: Double = 100.0

    /// UserDefaults key for an optional plan-price override.
    private static let planPriceKey = "planMonthlyPrice"

    /// Refresh interval for the periodic rescan (10 minutes).
    private static let refreshInterval: TimeInterval = 600

    // MARK: Per-model pricing (USD per token)

    /// Pricing rates for one model family.
    private struct Pricing {
        let input: Double
        let output: Double
        let cacheWrite: Double   // cache_creation_input_tokens
        let cacheRead: Double    // cache_read_input_tokens
    }

    private static let opusPricing   = Pricing(input: 15e-6,  output: 75e-6,  cacheWrite: 18.75e-6, cacheRead: 1.5e-6)
    private static let sonnetPricing = Pricing(input: 3e-6,   output: 15e-6,  cacheWrite: 3.75e-6,  cacheRead: 0.3e-6)
    private static let haikuPricing  = Pricing(input: 1e-6,   output: 5e-6,   cacheWrite: 1.25e-6,  cacheRead: 0.1e-6)

    /// Map a model string to its pricing. Defaults to sonnet for unknowns.
    private static func pricing(for model: String) -> Pricing {
        let m = model.lowercased()
        if m.contains("opus")  { return opusPricing }
        if m.contains("haiku") { return haikuPricing }
        if m.contains("sonnet") { return sonnetPricing }
        return sonnetPricing
    }

    // MARK: Concurrency

    /// Serial background queue for all IO and computation.
    private let queue = DispatchQueue(label: "ClaudeStatsMonitor.work", qos: .utility)
    private var timer: DispatchSourceTimer?

    // MARK: Per-file cache (performance)

    /// Cached per-day aggregation for a single file, keyed off its size so an
    /// unchanged file can be skipped on subsequent scans.
    private struct FileCacheEntry: Codable {
        let fileSize: Int
        let perDay: [String: DayBucket]
    }

    /// Mutable accumulator for one calendar day.
    private struct DayBucket: Codable {
        var tokens: Int = 0
        var cost: Double = 0
    }

    /// On-disk location for the persisted per-file cache (so restarts are instant).
    private static var cacheFileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("com.julian.dynamicisland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("statscache.json")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheFileURL),
              let decoded = try? JSONDecoder().decode([String: FileCacheEntry].self, from: data) else { return }
        fileCache = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(fileCache) else { return }
        try? data.write(to: Self.cacheFileURL, options: .atomic)
    }

    /// Cache keyed by absolute file path. Only touched on the background queue.
    private var fileCache: [String: FileCacheEntry] = [:]

    // MARK: Date helpers

    /// Calendar pinned to the current local time zone for day/month bucketing.
    private static func localCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    /// "yyyy-MM-dd" formatter in the local time zone.
    private static func dayKeyFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Short "dd.MM" label formatter in the local time zone.
    private static func labelFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "dd.MM"
        return f
    }

    // MARK: Lifecycle

    /// Compute immediately on the background queue, then refresh periodically.
    func start() {
        queue.async { [weak self] in
            self?.loadCache()      // instant restarts: skip unchanged files
            self?.recompute()
        }

        // Recompute (e.g. recommendation) when the plan price changes in settings.
        NotificationCenter.default.addObserver(forName: .diSettingsChanged, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.recompute() }
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.refreshInterval,
                   repeating: Self.refreshInterval)
        t.setEventHandler { [weak self] in
            self?.recompute()
        }
        timer = t
        t.resume()
    }

    /// Cancel the periodic refresh.
    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: Core computation

    /// Full scan + aggregation. Runs on `queue`. Publishes on main if changed.
    private func recompute() {
        // Global per-day totals, merged from every file's cached/recomputed map.
        var global: [String: DayBucket] = [:]

        for fileURL in jsonlFiles() {
            let path = fileURL.path
            let size = fileSize(of: fileURL)

            let perDay: [String: DayBucket]
            if let cached = fileCache[path], cached.fileSize == size {
                // Unchanged file: reuse the cached aggregation.
                perDay = cached.perDay
            } else {
                // New or changed file: re-read and recompute, then cache.
                perDay = parseFile(at: fileURL)
                fileCache[path] = FileCacheEntry(fileSize: size, perDay: perDay)
            }

            // Merge this file's per-day map into the global totals.
            for (day, bucket) in perDay {
                var g = global[day] ?? DayBucket()
                g.tokens += bucket.tokens
                g.cost += bucket.cost
                global[day] = g
            }
        }

        // Drop cache entries for files that no longer exist, then persist.
        let livePaths = Set(jsonlFiles().map { $0.path })
        fileCache = fileCache.filter { livePaths.contains($0.key) }
        saveCache()

        let newStats = buildStats(from: global)

        if ProcessInfo.processInfo.environment["DI_DEBUG"] == "1" {
            FileHandle.standardError.write("DI_STATS total=\(newStats.totalTokens) cost=$\(Int(newStats.totalCost)) month=$\(Int(newStats.monthCost)) today=\(newStats.todayTokens) days=\(newStats.last14Days.count) rec=\(newStats.recommendation)\n".data(using: .utf8)!)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.stats != newStats {
                self.stats = newStats
            }
        }
    }

    // MARK: File discovery

    /// All `*.jsonl` transcript files under `~/.claude/projects`.
    private func jsonlFiles() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "jsonl" {
                results.append(url)
            }
        }
        return results
    }

    /// Current size of a file in bytes, or 0 if unavailable.
    private func fileSize(of url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let n = attrs?[.size] as? NSNumber {
            return n.intValue
        }
        return 0
    }

    // MARK: File parsing

    /// Parse a single JSONL file into its per-day token/cost map.
    /// Defensive: never throws, skips malformed or irrelevant lines.
    private func parseFile(at url: URL) -> [String: DayBucket] {
        var perDay: [String: DayBucket] = [:]

        // Read the whole file as data; bail out gracefully on failure.
        guard let data = try? Data(contentsOf: url) else { return perDay }
        guard let text = String(data: data, encoding: .utf8) else { return perDay }

        let dayFmt = Self.dayKeyFormatter()

        // ISO8601 formatters are created per file (they are not Sendable and
        // must not be shared across the concurrent work the queue performs).
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        // Split into lines without allocating intermediate substrings eagerly.
        text.enumerateLines { line, _ in
            // Skip obviously empty lines.
            if line.isEmpty { return }
            // Fast reject: only assistant usage lines carry "output_tokens". This avoids
            // JSON-parsing the huge user/tool-result lines (the real bottleneck on 200MB+).
            if !line.contains("output_tokens") { return }
            guard let lineData = line.data(using: .utf8) else { return }

            // Parse defensively; any malformed line is silently skipped.
            guard
                let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                let message = obj["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else {
                return
            }

            // Extract token counts (missing -> 0).
            let input = Self.intValue(usage["input_tokens"])
            let output = Self.intValue(usage["output_tokens"])
            let cacheCreate = Self.intValue(usage["cache_creation_input_tokens"])
            let cacheRead = Self.intValue(usage["cache_read_input_tokens"])

            let rawTokens = input + output + cacheCreate + cacheRead

            // Estimate cost via per-model pricing.
            let model = (message["model"] as? String) ?? ""
            let p = Self.pricing(for: model)
            let cost =
                Double(input) * p.input +
                Double(output) * p.output +
                Double(cacheCreate) * p.cacheWrite +
                Double(cacheRead) * p.cacheRead

            // Bucket by local calendar day using the message timestamp.
            guard
                let tsString = obj["timestamp"] as? String,
                let date = (isoFractional.date(from: tsString) ?? isoPlain.date(from: tsString))
            else {
                return
            }

            let dayKey = dayFmt.string(from: date)
            var bucket = perDay[dayKey] ?? DayBucket()
            bucket.tokens += rawTokens
            bucket.cost += cost
            perDay[dayKey] = bucket
        }

        return perDay
    }

    /// Coerce a JSON numeric value to Int, tolerating String/NSNumber forms.
    private static func intValue(_ any: Any?) -> Int {
        if let n = any as? NSNumber { return n.intValue }
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }

    // MARK: Stats assembly

    /// Build the final `ClaudeStats` from the global per-day buckets.
    private func buildStats(from global: [String: DayBucket]) -> ClaudeStats {
        let cal = Self.localCalendar()
        let dayFmt = Self.dayKeyFormatter()
        let labelFmt = Self.labelFormatter()

        let now = Date()
        let todayKey = dayFmt.string(from: now)

        // Current local month range for month aggregation.
        let nowComponents = cal.dateComponents([.year, .month], from: now)

        // Lifetime + month sums.
        var totalTokens = 0
        var totalCost = 0.0
        var monthTokens = 0
        var monthCost = 0.0

        for (dayKey, bucket) in global {
            totalTokens += bucket.tokens
            totalCost += bucket.cost

            // A day belongs to "this month" if its parsed date shares year+month.
            if let dayDate = dayFmt.date(from: dayKey) {
                let c = cal.dateComponents([.year, .month], from: dayDate)
                if c.year == nowComponents.year && c.month == nowComponents.month {
                    monthTokens += bucket.tokens
                    monthCost += bucket.cost
                }
            }
        }

        let todayTokens = global[todayKey]?.tokens ?? 0

        // Build the trailing 14-day window (oldest first, today last), filling gaps.
        var last14: [DailyUsage] = []
        // Start of "today" in the local calendar.
        let startOfToday = cal.startOfDay(for: now)
        for offset in stride(from: 13, through: 0, by: -1) {
            guard let dayDate = cal.date(byAdding: .day, value: -offset, to: startOfToday) else {
                continue
            }
            let key = dayFmt.string(from: dayDate)
            let label = labelFmt.string(from: dayDate)
            let bucket = global[key] ?? DayBucket()
            last14.append(DailyUsage(day: key,
                                     label: label,
                                     tokens: bucket.tokens,
                                     cost: bucket.cost))
        }

        // Plan price: UserDefaults override or default.
        let planPrice = Self.resolvedPlanPrice()

        let recommendation = Self.recommendation(monthCost: monthCost, planPrice: planPrice)

        return ClaudeStats(
            totalTokens: totalTokens,
            totalCost: totalCost,
            monthTokens: monthTokens,
            monthCost: monthCost,
            todayTokens: todayTokens,
            last14Days: last14,
            planMonthlyPrice: planPrice,
            recommendation: recommendation,
            valid: true
        )
    }

    /// Resolve the configured plan price, falling back to the default.
    private static func resolvedPlanPrice() -> Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: planPriceKey) != nil {
            let value = defaults.double(forKey: planPriceKey)
            if value > 0 { return value }
        }
        return defaultPlanMonthlyPrice
    }

    /// Build the German recommendation string based on month value vs plan price.
    private static func recommendation(monthCost: Double, planPrice: Double) -> String {
        // Guard against a zero/invalid plan price to avoid division by zero.
        let safePlan = planPrice > 0 ? planPrice : defaultPlanMonthlyPrice
        let ratio = monthCost / safePlan

        let m = Int(monthCost), p = Int(safePlan), x = Int(ratio)
        if ratio >= 2.0 {
            return L("Plan pays off big – you get ~\(x)× its price in value. A higher tier may be worth it if you hit limits often.",
                     "Abo lohnt sich massiv – du holst ~\(x)× den Preis raus. Ein höheres Limit (Upgrade) kann sich lohnen, wenn du oft anstößt.")
        } else if ratio >= 1.0 {
            return L("Plan pays off – clearly worth it (≈ $\(m) API value this month).",
                     "Abo lohnt sich – du holst den Preis klar raus (≈ $\(m) API-Wert diesen Monat).")
        } else if ratio >= 0.5 {
            return L("Roughly break-even (≈ $\(m) API value vs. $\(p) plan).",
                     "Abo ist grob im Break-even (≈ $\(m) API-Wert vs. $\(p) Abo).")
        } else {
            return L("Only ≈ $\(m) API value – below the $\(p) plan. A cheaper plan might be enough.",
                     "Du nutzt nur ≈ $\(m) API-Wert – unter den $\(p) Abo. Ein günstigeres Abo könnte reichen.")
        }
    }
}
