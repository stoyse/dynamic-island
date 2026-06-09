import AppKit
import SwiftUI
import Combine

/// Which detail content the expanded island shows.
enum IslandMode { case music, claude }

/// Drives the collapsed/expanded animation + mode from the AppKit hover layer into SwiftUI.
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var mode: IslandMode = .music
}

/// All notch / window dimensions, derived from the physical display.
struct NotchGeometry {
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let collapsedWidth: CGFloat
    let collapsedHeight: CGFloat
    let expandedWidth: CGFloat
    let musicHeight: CGFloat
    let claudeHeight: CGFloat

    var expandedHeight: CGFloat { max(musicHeight, claudeHeight) }

    /// Extra height the expanded island gains for the "update available" banner.
    static let updateBannerHeight: CGFloat = 46

    func height(for mode: IslandMode, extra: CGFloat = 0) -> CGFloat {
        (mode == .claude ? claudeHeight : musicHeight) + extra
    }

    /// The full window frame (screen coords, bottom-left origin) for a given state.
    /// The window is sized to *exactly* the visible island so that, when collapsed,
    /// no window covers the dropdown area below — leaving it fully clickable.
    func windowFrame(expanded: Bool, mode: IslandMode, extra: CGFloat = 0) -> NSRect {
        let f = screen.frame
        let w = expanded ? expandedWidth : collapsedWidth
        let h = expanded ? height(for: mode, extra: extra) : collapsedHeight
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
    }

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first!
        // Use the exact notch height; 38 (typical) only if the inset isn't ready yet.
        let notchH: CGFloat = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 38
        var notchW: CGFloat = 220
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let w = r.minX - l.maxX
            if w > 80 { notchW = w }
        }
        let arm: CGFloat = 40
        let expandArm: CGFloat = 190
        return NotchGeometry(
            screen: screen,
            notchWidth: notchW,
            notchHeight: notchH,
            collapsedWidth: notchW + 2 * arm,
            collapsedHeight: notchH,
            expandedWidth: notchW + 2 * expandArm,
            musicHeight: 162,
            claudeHeight: 188
        )
    }
}

/// Borderless, non-activating floating panel that draws over the menu bar.
final class NotchPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = false   // would force level to .floating (below the menu bar)
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        // Above the status-item level so the island sits over the menu bar / notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
    }

    // Allow becoming key on click so SwiftUI taps/controls register. As a
    // .nonactivatingPanel this does NOT activate the app or switch the menu bar.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Don't let AppKit push us below the menu bar — we sit flush with the screen top.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

/// Hosts the SwiftUI island. Hover toggles expansion; when collapsed the whole
/// (tiny) window is click-through so the area below stays usable.
final class IslandContainerView: NSView {
    private let state: IslandState

    init(state: IslandState, hosting: NSView) {
        self.state = state
        super.init(frame: .zero)
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Collapsed → fully click-through (nothing to interact with; the dropdown
        // area below isn't even covered). Expanded → normal hit testing for controls.
        state.expanded ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        if !state.expanded { state.expanded = true }
    }
    override func mouseExited(with event: NSEvent) {
        if state.expanded { state.expanded = false }
    }
}

/// Owns the panel + state, resizes the window to match the live island, and keeps
/// it positioned on screen changes.
final class NotchController {
    private(set) var geo: NotchGeometry
    let state = IslandState()
    private let panel: NotchPanel
    private let spotify: SpotifyMonitor
    private let usage: ClaudeUsageMonitor
    private let stats: ClaudeStatsMonitor
    private let updater: UpdateChecker
    private var hosting: NSHostingView<IslandView>!
    private var cancellables = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?

    init(spotify: SpotifyMonitor, usage: ClaudeUsageMonitor, stats: ClaudeStatsMonitor, updater: UpdateChecker) {
        self.spotify = spotify
        self.usage = usage
        self.stats = stats
        self.updater = updater
        self.geo = NotchGeometry.current()
        self.panel = NotchPanel(size: CGSize(width: geo.collapsedWidth, height: geo.collapsedHeight))

        let root = IslandView(spotify: spotify, usage: usage, stats: stats, updater: updater, state: state, geo: geo)
        self.hosting = NSHostingView(rootView: root)
        hosting.layer?.backgroundColor = .clear
        let container = IslandContainerView(state: state, hosting: hosting)
        panel.contentView = container
        panel.setFrame(geo.windowFrame(expanded: false, mode: .music), display: true)
        panel.orderFrontRegardless()

        // safeAreaInsets (the notch height) can be 0 at launch → re-measure shortly
        // after so the collapsed island matches the real notch instead of the fallback.
        for delay in [0.4, 1.2, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reposition() }
        }

        // Resize the window whenever the island opens/closes, switches mode, or an
        // update appears/disappears (the expanded island grows for the banner).
        state.$expanded.removeDuplicates()
            .sink { [weak self] _ in self?.updateWindow() }
            .store(in: &cancellables)
        state.$mode.removeDuplicates()
            .sink { [weak self] _ in self?.updateWindow() }
            .store(in: &cancellables)
        updater.$available.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateWindow() }
            .store(in: &cancellables)
        usage.$access.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateWindow() }
            .store(in: &cancellables)
    }

    /// Extra height for the top banner (update available or a keychain warning).
    private var bannerExtra: CGFloat {
        let warn = usage.access == .denied || usage.access == .missing
        return (state.expanded && (warn || updater.available != nil)) ? NotchGeometry.updateBannerHeight : 0
    }

    /// Set the window frame for the current state. Growing is immediate (the content
    /// animates into it); shrinking is delayed so the collapse animation can play.
    private func updateWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let target = self.geo.windowFrame(expanded: self.state.expanded, mode: self.state.mode, extra: self.bannerExtra)
            self.collapseWork?.cancel()
            self.collapseWork = nil

            let cur = self.panel.frame
            let shrinking = target.width < cur.width - 1 || target.height < cur.height - 1
            if shrinking {
                let work = DispatchWorkItem { [weak self] in
                    self?.panel.setFrame(target, display: true, animate: false)
                    self?.panel.orderFrontRegardless()
                }
                self.collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
            } else {
                self.panel.setFrame(target, display: true, animate: false)
                self.panel.orderFrontRegardless()
            }
        }
    }

    func reposition() {
        let newGeo = NotchGeometry.current()
        let changed = newGeo.notchHeight != geo.notchHeight
            || newGeo.notchWidth != geo.notchWidth
            || newGeo.screen != geo.screen
        geo = newGeo
        // Rebuild the SwiftUI tree with the new geometry so the island (esp. the
        // collapsed notch height) actually reflects it — IslandView holds geo by value.
        if changed {
            hosting.rootView = IslandView(spotify: spotify, usage: usage, stats: stats,
                                          updater: updater, state: state, geo: geo)
        }
        updateWindow()
    }
}
