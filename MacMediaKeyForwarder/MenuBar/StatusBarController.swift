import Cocoa

/// Manages the `NSStatusItem`, its menu, and all menu actions.
final class StatusBarController: NSObject, NSMenuDelegate {

    private let preferences: AppPreferences
    private let eventTap: MediaKeyEventTap

    private var statusItem: NSStatusItem!
    private var pauseItems: [NSMenuItem] = []
    private var startupItem: NSMenuItem!
    private var hideFromMenuBarItem: NSMenuItem!

    /// Opens the settings / targets window (wired from `AppDelegate`).
    var onOpenSettings: (() -> Void)?

    init(preferences: AppPreferences, eventTap: MediaKeyEventTap) {
        self.preferences = preferences
        self.eventTap = eventTap
        super.init()
        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let bundleInfo = Bundle.main.infoDictionary ?? [:]
        let version = bundleInfo["CFBundleShortVersionString"] as? String ?? "?"
        let versionString = "Version \(version)"

        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: versionString, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let settingsItem = menu.addItem(
            withTitle: String(localized: "Targets & Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]

        menu.addItem(.separator())

        let pauseItem = menu.addItem(
            withTitle: String(localized: "Pause"),
            action: #selector(manualPause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItems.append(pauseItem)

        let autoPauseItem = menu.addItem(
            withTitle: String(localized: "Pause if no player is running"),
            action: #selector(autoPause),
            keyEquivalent: ""
        )
        autoPauseItem.target = self
        pauseItems.append(autoPauseItem)

        menu.addItem(.separator())

        startupItem = menu.addItem(
            withTitle: String(localized: "Open at login"),
            action: #selector(toggleStartupItem),
            keyEquivalent: ""
        )
        startupItem.target = self

        hideFromMenuBarItem = menu.addItem(
            withTitle: String(localized: "Hide from menu bar"),
            action: #selector(hideFromMenuBar),
            keyEquivalent: ""
        )
        hideFromMenuBarItem.target = self

        menu.addItem(.separator())

        let donateItem = menu.addItem(
            withTitle: String(localized: "Donate if you like the app"),
            action: #selector(support),
            keyEquivalent: ""
        )
        donateItem.target = self

        let updateItem = menu.addItem(
            withTitle: String(localized: "Check for updates"),
            action: #selector(update),
            keyEquivalent: ""
        )
        updateItem.target = self

        let quitItem = menu.addItem(
            withTitle: String(localized: "Quit"),
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self

        let image = NSImage(named: "icon")
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "Mac Media Key Forwarder"
        statusItem.button?.image = image
        statusItem.menu = menu
        statusItem.behavior = .removalAllowed
        statusItem.isVisible = !preferences.hideFromMenuBar

        updatePauseCheckmarks()
        updateStartupItemCheckmark()
    }

    // MARK: - Public

    func showStatusItem() {
        if preferences.hideFromMenuBar {
            preferences.hideFromMenuBar = false
            statusItem.isVisible = true
        }
    }

    // MARK: - Pause Actions

    @objc private func manualPause() {
        if preferences.pauseMode != .paused {
            preferences.pauseMode = .paused
            eventTap.stopListening()
        } else {
            preferences.pauseMode = .none
            eventTap.startListening()
        }
        updatePauseCheckmarks()
    }

    @objc private func autoPause() {
        if preferences.pauseMode != .automatic {
            preferences.pauseMode = .automatic
        } else {
            preferences.pauseMode = .none
        }
        updatePauseCheckmarks()
        eventTap.startListening()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    // MARK: - Other Actions

    @objc private func toggleStartupItem() {
        LoginItemManager.toggle()
        updateStartupItemCheckmark()
    }

    @objc private func hideFromMenuBar() {
        preferences.hideFromMenuBar = true
        LoginItemManager.ensureRegistered()
        statusItem.isVisible = false
    }

    @objc private func support() {
        NSWorkspace.shared.open(URL(string: "https://paypal.me/philippgmeyer")!)
    }

    @objc private func update() {
        NSWorkspace.shared.open(URL(string: "https://github.com/Quppi/macmediakeyforwarder/releases")!)
    }

    @objc private func quit() {
        eventTap.stopListening()
        NSApp.terminate(nil)
    }

    // MARK: - UI State

    private func updatePauseCheckmarks() {
        pauseItems[0].state = preferences.pauseMode == .paused ? .on : .off
        pauseItems[1].state = preferences.pauseMode == .automatic ? .on : .off
    }

    private func updateStartupItemCheckmark() {
        startupItem.state = LoginItemManager.isLoginItem ? .on : .off
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updateStartupItemCheckmark()
    }
}
