import AppKit
import Combine
import Foundation

/// Publishes the currently playing media (Spotify primary, YouTube-in-Chrome fallback).
///
/// Polling happens on a background queue every ~1.5s. All `@Published` mutations
/// are hopped onto the main thread. AppleScript calls are wrapped in error
/// handling so a scripting failure can never crash the app.
final class SpotifyMonitor: ObservableObject {

    // MARK: Published state

    @Published private(set) var nowPlaying: NowPlaying? = nil

    // MARK: Private state

    /// Timer driving the poll loop. Created/torn down by start()/stop().
    private var timer: DispatchSourceTimer?

    /// Dedicated background queue for AppleScript + the poll timer.
    private let queue = DispatchQueue(label: "SpotifyMonitor.poll", qos: .utility)

    /// The last artwork URL string we downloaded; used to avoid redundant downloads.
    private var lastArtworkURLString: String?

    /// The currently cached artwork image (matches `lastArtworkURLString`).
    private var cachedArtwork: NSImage?

    /// Generation counter so a stale async artwork download can't clobber newer state.
    private var artworkGeneration: UInt64 = 0

    /// Reusable URLSession for artwork downloads.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        return URLSession(configuration: cfg)
    }()

    private let pollInterval: TimeInterval = 1.5

    // MARK: Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            // Avoid double-starting.
            guard self.timer == nil else { return }

            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now(), repeating: self.pollInterval, leeway: .milliseconds(200))
            t.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = t
            t.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
        }
    }

    deinit {
        timer?.cancel()
        timer = nil
    }

    // MARK: Playback control (Spotify)

    /// Toggle play/pause. Optimistically flips local state, then polls.
    func playPause() { control("playpause") }
    func nextTrack() { control("next track") }
    func previousTrack() { control("previous track") }

    /// Bring the playing app to the front, showing the current song.
    func revealInApp(source: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            if source == "YouTube" {
                _ = self.runAppleScript("if application \"Google Chrome\" is running then tell application \"Google Chrome\" to activate")
            } else {
                _ = self.runAppleScript("if application \"Spotify\" is running then tell application \"Spotify\" to activate")
            }
        }
    }

    /// Seek to an absolute position (seconds) in the current Spotify track.
    func seek(to seconds: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            let s = max(0, seconds)
            _ = self.runAppleScript("if application \"Spotify\" is running then tell application \"Spotify\" to set player position to \(s)")
            // Re-poll quickly so the UI reflects the new position.
            self.poll()
        }
    }

    private func control(_ command: String) {
        queue.async { [weak self] in
            guard let self else { return }
            _ = self.runAppleScript("if application \"Spotify\" is running then tell application \"Spotify\" to \(command)")
            // Re-poll quickly so the UI reflects the new state.
            self.poll()
        }
    }

    // MARK: Polling

    /// One poll cycle. Runs on `queue`.
    private func poll() {
        // Try Spotify first.
        let spotify = readSpotify()

        if let s = spotify, s.state == "playing" {
            // Spotify is actively playing → use it.
            publishSpotify(s)
            return
        }

        // Spotify isn't playing — try YouTube in Chrome.
        if let yt = readYouTube() {
            publishYouTube(yt)
            return
        }

        // No YouTube. If Spotify is running but paused/stopped with a track, show it paused.
        if let s = spotify, !s.title.isEmpty {
            publishSpotify(s)
            return
        }

        // Nothing playing anywhere.
        publish(nil)
    }

    // MARK: - Spotify

    /// Parsed result of the Spotify AppleScript.
    private struct SpotifyResult {
        var state: String          // "playing" | "paused" | "stopped"
        var title: String
        var artist: String
        var artworkURL: String
        var duration: Double
        var position: Double
    }

    /// Run the verified Spotify AppleScript and parse its output. Returns nil on any failure.
    private func readSpotify() -> SpotifyResult? {
        let script = """
        if application "Spotify" is running then tell application "Spotify" to return (player state as text) & "\\n" & (name of current track) & "\\n" & (artist of current track) & "\\n" & (artwork url of current track) & "\\n" & ((duration of current track) / 1000) & "\\n" & (player position)
        """

        guard let raw = runAppleScript(script) else { return nil }

        // If Spotify isn't running, the AppleScript returns no value → empty string.
        let lines = raw.components(separatedBy: "\n")
        guard lines.count >= 1 else { return nil }

        func line(_ i: Int) -> String {
            guard i < lines.count else { return "" }
            return lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let state = line(0).lowercased()
        // A valid state is required; otherwise we have nothing useful.
        guard state == "playing" || state == "paused" || state == "stopped" else { return nil }

        let title = line(1)
        let artist = line(2)
        let artworkURL = line(3)
        let duration = Double(line(4)) ?? 0
        let position = Double(line(5)) ?? 0

        return SpotifyResult(
            state: state,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            duration: duration,
            position: position
        )
    }

    private func publishSpotify(_ s: SpotifyResult) {
        let np = NowPlaying(
            title: s.title,
            artist: s.artist,
            isPlaying: s.state == "playing",
            source: "Spotify",
            artwork: nil,            // filled in by publish() from cache
            duration: s.duration,
            position: s.position
        )
        publish(np, artworkURL: s.artworkURL)
    }

    // MARK: - YouTube (Chrome)

    private struct YouTubeResult {
        var title: String
        var videoID: String
    }

    /// Read the active Chrome tab and, if it's a YouTube watch page, extract id + title.
    private func readYouTube() -> YouTubeResult? {
        let script = """
        if application "Google Chrome" is running then tell application "Google Chrome" to if (count of windows) > 0 then return (URL of active tab of front window) & "\\n" & (title of active tab of front window)
        """

        guard let raw = runAppleScript(script) else { return nil }

        let lines = raw.components(separatedBy: "\n")
        guard lines.count >= 1 else { return nil }

        let urlString = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return nil }

        var title = lines.count >= 2
            ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        guard let videoID = youTubeVideoID(from: urlString) else { return nil }

        // Strip a trailing " - YouTube" from the tab title.
        let suffix = " - YouTube"
        if title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if title.isEmpty { title = "YouTube" }

        return YouTubeResult(title: title, videoID: videoID)
    }

    /// Extract a YouTube video id from a watch URL, or nil if it isn't one.
    private func youTubeVideoID(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let host = comps.host?.lowercased() else { return nil }

        // youtu.be/<id>
        if host.contains("youtu.be") {
            let id = comps.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .components(separatedBy: "/")
                .first ?? ""
            return id.isEmpty ? nil : sanitizeVideoID(id)
        }

        // youtube.com/watch?v=<id>
        if host.contains("youtube.com") {
            // Must be a watch page.
            guard comps.path == "/watch" || comps.path.hasPrefix("/watch") else { return nil }
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return sanitizeVideoID(v)
            }
            return nil
        }

        return nil
    }

    /// Keep only the leading id token (defensive against stray characters).
    private func sanitizeVideoID(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let trimmed = raw.unicodeScalars.prefix { allowed.contains($0) }
        let id = String(String.UnicodeScalarView(trimmed))
        return id.isEmpty ? nil : id
    }

    private func publishYouTube(_ yt: YouTubeResult) {
        let artworkURL = "https://img.youtube.com/vi/\(yt.videoID)/hqdefault.jpg"
        let np = NowPlaying(
            title: yt.title,
            artist: "YouTube",
            isPlaying: true,         // best effort — we can't easily know
            source: "YouTube",
            artwork: nil,            // filled in by publish() from cache
            duration: 0,
            position: 0
        )
        publish(np, artworkURL: artworkURL)
    }

    // MARK: - AppleScript helper

    /// Execute an AppleScript source string. Never throws/crashes; returns nil on error.
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if ProcessInfo.processInfo.environment["DI_DEBUG"] == "1" {
                let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                FileHandle.standardError.write("DI_APPLESCRIPT_ERROR code=\(code) info=\(errorInfo)\n".data(using: .utf8)!)
            }
            // Scripting error (app not scriptable, permission denied, etc.) — ignore.
            return nil
        }
        if ProcessInfo.processInfo.environment["DI_DEBUG"] == "1" {
            FileHandle.standardError.write("DI_APPLESCRIPT_OK len=\((result.stringValue ?? "").count)\n".data(using: .utf8)!)
        }
        // A void/empty result means "nothing" (e.g. app not running).
        guard let str = result.stringValue else { return nil }
        return str
    }

    // MARK: - Publishing + artwork

    /// Publish a new now-playing value. Reuses cached artwork when the artwork URL
    /// is unchanged, otherwise kicks off an async download.
    ///
    /// - Parameter artworkURL: the artwork URL string (nil clears artwork).
    private func publish(_ value: NowPlaying?, artworkURL: String? = nil) {
        guard var value else {
            // Clearing now-playing entirely.
            lastArtworkURLString = nil
            cachedArtwork = nil
            artworkGeneration &+= 1
            commit(nil)
            return
        }

        if let urlString = artworkURL, !urlString.isEmpty {
            if urlString == lastArtworkURLString {
                // Same artwork as before — reuse the cache.
                value.artwork = cachedArtwork
                commit(value)
            } else {
                // New artwork. Publish immediately without art, then download.
                lastArtworkURLString = urlString
                cachedArtwork = nil
                artworkGeneration &+= 1
                let generation = artworkGeneration

                value.artwork = nil
                commit(value)

                downloadArtwork(urlString, generation: generation)
            }
        } else {
            // No artwork URL.
            lastArtworkURLString = nil
            cachedArtwork = nil
            value.artwork = nil
            commit(value)
        }
    }

    /// Asynchronously download artwork and, if still current, attach it to nowPlaying.
    private func downloadArtwork(_ urlString: String, generation: UInt64) {
        guard let url = URL(string: urlString) else { return }

        let task = session.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            guard error == nil, let data, let image = NSImage(data: data) else { return }

            // Re-enter our serial queue to safely check generation + caches.
            self.queue.async {
                // A newer track/artwork may have superseded this download.
                guard generation == self.artworkGeneration else { return }
                self.cachedArtwork = image

                // Update the currently published value with the artwork.
                DispatchQueue.main.async {
                    guard var current = self.nowPlaying else { return }
                    current.artwork = image
                    self.nowPlaying = current
                }
            }
        }
        task.resume()
    }

    /// Commit a value to `nowPlaying` on the main thread, but only when the
    /// "identity" (title+artist+isPlaying+source) actually changed. Artwork-only
    /// updates are handled separately in downloadArtwork().
    private func commit(_ value: NowPlaying?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let current = self.nowPlaying

            // Clearing.
            guard let value else {
                if current != nil { self.nowPlaying = nil }
                return
            }

            // Determine whether the meaningful fields changed.
            let changed: Bool
            if let current {
                changed = current.title != value.title
                    || current.artist != value.artist
                    || current.isPlaying != value.isPlaying
                    || current.source != value.source
            } else {
                changed = true
            }

            // Also update if we now have artwork the current value lacks (or vice-versa)
            // for the same track, so reused-cache art appears.
            let artworkAppeared = !changed
                && current?.artwork == nil
                && value.artwork != nil

            // Keep the playback position live for the same track so the seek bar
            // advances between identity changes. We republish whenever the position
            // moved by more than a poll's worth, or jumped backwards (a seek).
            let positionMoved = !changed && current != nil
                && abs((current?.position ?? 0) - value.position) > 0.4

            if changed || artworkAppeared || positionMoved {
                self.nowPlaying = value
            }
        }
    }
}
