import AppKit
import Combine
import Foundation

/// A newer release found on GitHub.
struct UpdateInfo: Equatable {
    var version: String        // "1.1.0"
    var tag: String            // "v1.1.0"
    var assetURL: URL          // .zip (preferred) or .dmg
    var assetName: String
    var isZip: Bool
}

/// Where the one-click update is in its lifecycle.
enum UpdateState: Equatable {
    case idle
    case downloading(Double)   // 0...1
    case installing
    case failed(String)
}

/// Polls the public GitHub releases for a newer build and installs it in one click:
/// download → unpack → swap the running .app → relaunch. No DMG, no wizard.
final class UpdateChecker: ObservableObject {
    @Published private(set) var available: UpdateInfo? = nil
    @Published private(set) var state: UpdateState = .idle

    private let repo = "stoyse/dynamic-island"
    private let session = URLSession(configuration: .default)
    private var timer: Timer?
    private var progressObs: NSKeyValueObservation?

    // MARK: Lifecycle

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // MARK: Check

    func check() {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DynamicIsland", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Self.isNewer(latest, than: self.currentVersion) else {
                DispatchQueue.main.async { if self.available != nil { self.available = nil } }
                return
            }

            let assets = (json["assets"] as? [[String: Any]]) ?? []
            func asset(_ ext: String) -> (String, URL)? {
                for a in assets {
                    if let n = a["name"] as? String, n.lowercased().hasSuffix(ext),
                       let s = a["browser_download_url"] as? String, let u = URL(string: s) {
                        return (n, u)
                    }
                }
                return nil
            }

            let info: UpdateInfo?
            if let (n, u) = asset(".zip") {
                info = UpdateInfo(version: latest, tag: tag, assetURL: u, assetName: n, isZip: true)
            } else if let (n, u) = asset(".dmg") {
                info = UpdateInfo(version: latest, tag: tag, assetURL: u, assetName: n, isZip: false)
            } else {
                info = nil
            }
            DispatchQueue.main.async { self.available = info }
        }.resume()
    }

    /// Semantic-ish "a > b" over dot-separated integer components.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Install (one click)

    func installUpdate() {
        guard let info = available, state == .idle || isFailed else { return }
        state = .downloading(0)

        let task = session.downloadTask(with: info.assetURL) { [weak self] tmp, _, err in
            guard let self else { return }
            guard let tmp, err == nil else {
                DispatchQueue.main.async { self.state = .failed(L("Download failed", "Download fehlgeschlagen")) }
                return
            }
            DispatchQueue.main.async { self.state = .installing }
            self.performInstall(downloaded: tmp, info: info)
        }
        progressObs = task.progress.observe(\Progress.fractionCompleted) {
            [weak self] (progress: Progress, _: NSKeyValueObservedChange<Double>) in
            let f = progress.fractionCompleted
            DispatchQueue.main.async { self?.state = .downloading(f) }
        }
        task.resume()
    }

    private var isFailed: Bool { if case .failed = state { return true } else { return false } }

    private func performInstall(downloaded: URL, info: UpdateInfo) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("di-update-\(UUID().uuidString)")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)

        let dl = work.appendingPathComponent(info.assetName)
        try? fm.copyItem(at: downloaded, to: dl)

        var newApp: String?
        if info.isZip {
            if run("/usr/bin/ditto", ["-x", "-k", dl.path, work.path]) {
                newApp = findApp(in: work)
            }
        } else if let mount = attachDMG(dl.path) {
            if let app = findApp(in: URL(fileURLWithPath: mount)) {
                let dest = work.appendingPathComponent("DynamicIsland.app")
                try? fm.copyItem(at: URL(fileURLWithPath: app), to: dest)
                newApp = dest.path
            }
            _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet"])
        }

        guard let newApp else {
            DispatchQueue.main.async { self.state = .failed(L("Invalid update package", "Update-Paket ungültig")) }
            return
        }

        // Hand the swap to a detached helper: wait for us to quit, replace the bundle, relaunch.
        let dest = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        STAGE="\(dest).new"
        rm -rf "$STAGE"
        cp -R "\(newApp)" "$STAGE" || exit 1
        rm -rf "\(dest)"
        mv "$STAGE" "\(dest)"
        xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null
        open "\(dest)"
        """
        let scriptURL = work.appendingPathComponent("update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async { self.state = .failed(L("Could not stage update", "Update konnte nicht vorbereitet werden")) }
            return
        }
        _ = run("/bin/chmod", ["+x", scriptURL.path])

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptURL.path]
        do { try p.run() } catch {
            DispatchQueue.main.async { self.state = .failed(L("Could not launch updater", "Updater-Start fehlgeschlagen")) }
            return
        }

        // Quit so the helper can replace the bundle, then relaunch us.
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: Shell helpers

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func attachDMG(_ path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", path, "-nobrowse", "-readonly", "-noverify", "-noautoopen"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let out = String(data: data, encoding: .utf8) ?? ""
        for line in out.components(separatedBy: "\n") {
            if let r = line.range(of: "/Volumes/") {
                return String(line[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func findApp(in dir: URL) -> String? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return items.first(where: { $0.pathExtension == "app" })?.path
    }
}
