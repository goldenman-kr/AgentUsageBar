import AppKit

// AppKit entry point. Using an explicit entry (rather than SwiftUI's `App`)
// gives full control over the accessory activation policy and the status item.
//
// The process entry point always runs on the main thread, so we assert main-actor
// isolation to construct the @MainActor `AppDelegate` (and its view model).
// `app.run()` blocks inside the closure until termination, keeping `delegate`
// (held weakly by NSApplication) alive for the app's lifetime.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
