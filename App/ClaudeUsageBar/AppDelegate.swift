import AppKit
import SwiftUI
import Combine
import ClaudeUsageCore

/// Owns the `NSStatusItem` (menu-bar entry) and the popover that hosts the
/// SwiftUI `PopoverView`. AppKit is used directly for precise control over the
/// dynamic title and the accessory (no-Dock-icon) lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = UsageViewModel()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                   accessibilityDescription: "Claude 사용량")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = " ––"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = true
        let hosting = NSHostingController(rootView: PopoverView(model: model))
        // Report the SwiftUI content's true size to the popover. Without this the
        // hosting controller can over-report its height, making NSPopover think it
        // won't fit below the menu bar and flip it *above* — clipping the header
        // off the top of the screen.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // Update the menu-bar title whenever the snapshot changes.
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateStatusTitle() } }
            .store(in: &cancellables)

        // Refresh when the machine wakes from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        model.start()
        updateStatusTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    @objc private func didWake() {
        Task { await model.refresh() }
    }

    @MainActor private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let title = " " + model.menuBarTitle
        let color: NSColor
        switch model.peakUtilization {
        case ..<70: color = .controlTextColor
        case 70..<90: color = .systemOrange
        default: color = .systemRed
        }
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
        )
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        Task { await model.refresh() }
        // `.transient` behavior dismisses the popover on any outside interaction,
        // so no manual global event monitor is needed (and none to leak).
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
