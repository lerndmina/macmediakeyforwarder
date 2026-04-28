import AppKit
import SwiftUI

/// Preferences window: while visible, the app uses a regular activation policy (Dock + app switcher).
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
        let rootView = SettingsView(preferences: preferences)
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        // Defer key ordering to the next turn so AppKit/SwiftUI layout is not re-entered from activation.
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
    }
}
