import Foundation
import Observation

// MARK: - Pause State

enum PauseMode: Int {
    /// Normal operation — forward all media key events.
    case none = 0
    /// Manually paused — do not forward any events.
    case paused = 1
    /// Automatic — only forward events when a player is running.
    case automatic = 2
}

// MARK: - Preferences

@Observable
final class AppPreferences {

    private enum Keys {
        static let targetsJSON = "player_targets_v1"
        static let migrated = "player_targets_migrated_v1"
        static let legacyPriority = "user_priority_option"
        static let pause = "user_pause_option"
        static let hideFromMenuBar = "user_hide_from_menu_bar_option"
        static let preferNowPlayingRouting = "prefer_now_playing_routing_v1"
    }

    /// Ordered whitelist of bundle IDs to consider for routing and auto-pause.
    var targets: [PlayerTarget] {
        didSet { persistTargets() }
    }

    /// When true, route keys to the current Now Playing client if it appears in `targets` (Media Remote path).
    var preferNowPlayingRouting: Bool {
        didSet {
            UserDefaults.standard.set(preferNowPlayingRouting, forKey: Keys.preferNowPlayingRouting)
            if oldValue != preferNowPlayingRouting {
                NotificationCenter.default.post(name: .mmkfPreferNowPlayingRoutingChanged, object: nil)
            }
        }
    }

    var pauseMode: PauseMode {
        didSet { UserDefaults.standard.set(pauseMode.rawValue, forKey: Keys.pause) }
    }

    var hideFromMenuBar: Bool {
        didSet { UserDefaults.standard.set(hideFromMenuBar, forKey: Keys.hideFromMenuBar) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.pauseMode = PauseMode(rawValue: defaults.integer(forKey: Keys.pause)) ?? .none
        self.hideFromMenuBar = defaults.bool(forKey: Keys.hideFromMenuBar)
        self.preferNowPlayingRouting = defaults.object(forKey: Keys.preferNowPlayingRouting) as? Bool ?? true

        if let data = defaults.data(forKey: Keys.targetsJSON),
           let decoded = try? JSONDecoder().decode([PlayerTarget].self, from: data),
           !decoded.isEmpty {
            self.targets = decoded
        } else if !defaults.bool(forKey: Keys.migrated) {
            let raw = defaults.integer(forKey: Keys.legacyPriority)
            self.targets = PlayerTarget.migratedSingleTarget(fromLegacyRaw: raw)
            defaults.set(true, forKey: Keys.migrated)
            persistTargets()
        } else {
            self.targets = BuiltInMediaPlayerBundle.orderedDefaults.map {
                PlayerTarget(bundleIdentifier: $0, displayName: nil)
            }
            persistTargets()
        }
    }

    private func persistTargets() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: Keys.targetsJSON)
        }
    }

    var targetBundleIdentifiers: [String] {
        targets.map(\.bundleIdentifier)
    }

    func displayName(for bundleID: String) -> String {
        if let t = targets.first(where: { $0.bundleIdentifier == bundleID }),
           let name = t.displayName, !name.isEmpty {
            return name
        }
        return BuiltInMediaPlayerBundle.defaultDisplayName(for: bundleID)
    }
}

extension Notification.Name {
    /// Posted when `preferNowPlayingRouting` changes so Media Remote polling can start or stop.
    static let mmkfPreferNowPlayingRoutingChanged = Notification.Name("eu.meyer.mmkf.preferNowPlayingRoutingChanged")
}
