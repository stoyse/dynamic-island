import Foundation
import Combine
import Security

/// Publishes the REAL Claude usage from Anthropic's OAuth usage endpoint
/// (`https://api.anthropic.com/api/oauth/usage`) — the same numbers shown in
/// Claude's settings and by Claude Code's `/usage`.
///
/// Notes:
/// - The endpoint is per-access-token rate limited and 429s aggressively, so we
///   poll only every 5 minutes and require a `User-Agent: claude-code/<ver>` header.
/// - The OAuth token is read from the macOS Keychain item Claude Code maintains
///   ("Claude Code-credentials"). We re-read it each poll so token refreshes by
///   Claude Code are picked up automatically.
final class ClaudeUsageMonitor: ObservableObject {

    @Published private(set) var usage: UsageInfo = .empty

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "ClaudeUsageMonitor.poll", qos: .utility)

    /// 5 minutes — safely above the ~180s floor the endpoint tolerates.
    private let pollInterval: TimeInterval = 300

    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let userAgent = "claude-code/2.1.159 (dynamic-island)"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    // MARK: Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 1, repeating: self.pollInterval, leeway: .seconds(10))
            t.setEventHandler { [weak self] in self?.poll() }
            self.timer = t
            t.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    deinit { timer?.cancel() }

    // MARK: Polling

    private func poll() {
        guard let token = readOAuthToken() else {
            publishNote(L("no token", "kein Token"))
            return
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            if error != nil { self.publishNote(L("offline", "offline")); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 { self.publishNote(L("usage check throttled", "Limit-Abfrage gedrosselt")); return }
            if code == 401 || code == 403 { self.publishNote(L("token expired", "Token abgelaufen")); return }
            guard code == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.publishNote("\(L("error", "Fehler")) \(code)")
                return
            }
            let info = self.parse(json)
            if ProcessInfo.processInfo.environment["DI_DEBUG"] == "1" {
                FileHandle.standardError.write("DI_USAGE_OK 5h=\(info.fiveHourPercent*100)% week=\(info.sevenDayPercent*100)% reset5h=\(String(describing: info.fiveHourReset))\n".data(using: .utf8)!)
            }
            self.publish(info)
        }
        task.resume()
    }

    /// Map the endpoint JSON into our UsageInfo. Utilization fields are 0...100.
    private func parse(_ json: [String: Any]) -> UsageInfo {
        func block(_ key: String) -> (Double, Date?)? {
            guard let b = json[key] as? [String: Any] else { return nil }
            let util = (b["utilization"] as? Double) ?? Double(b["utilization"] as? Int ?? 0)
            let reset = (b["resets_at"] as? String).flatMap(Self.parseDate)
            return (util / 100.0, reset)
        }

        let five = block("five_hour")
        let week = block("seven_day")
        let opus = block("seven_day_opus")

        return UsageInfo(
            fiveHourPercent: five?.0 ?? 0,
            fiveHourReset: five?.1,
            sevenDayPercent: week?.0 ?? 0,
            sevenDayReset: week?.1,
            opusPercent: opus?.0,
            opusReset: opus?.1,
            valid: true,
            statusNote: nil
        )
    }

    // MARK: Publishing

    private func publish(_ info: UsageInfo) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.usage != info { self.usage = info }
        }
    }

    /// Keep the last good numbers but attach a transient note (so the ring doesn't
    /// blank out on a single rate-limited / offline poll).
    private func publishNote(_ note: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var u = self.usage
            u.statusNote = note
            if self.usage != u { self.usage = u }
        }
    }

    // MARK: Keychain

    /// Read Claude Code's OAuth access token from the Keychain item it maintains
    /// ("Claude Code-credentials"). Done in-process via the Security framework so
    /// the one-time access dialog is correctly attributed to *this* app — clicking
    /// "Always Allow" then adds Dynamic Island to the item's ACL and all future
    /// reads are prompt-free (the access path Claude Code's secure store requires).
    private func readOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if ProcessInfo.processInfo.environment["DI_DEBUG"] == "1" {
                FileHandle.standardError.write("DI_KEYCHAIN status=\(status)\n".data(using: .utf8)!)
            }
            return nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }
        return token
    }

    // MARK: Date parsing

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func parseDate(_ s: String) -> Date? {
        isoFrac.date(from: s) ?? iso.date(from: s)
    }
}
