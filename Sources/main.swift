import AppKit

// Single-instance guard: if another copy is already running, bow out.
let myID = Bundle.main.bundleIdentifier ?? "com.julian.dynamicisland"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: myID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
