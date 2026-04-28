import AppKit
import Foundation

/// One entry in the user-configured media target whitelist (ordered).
struct PlayerTarget: Codable, Equatable, Identifiable, Hashable {
    var bundleIdentifier: String
    /// Optional display label; if nil, resolved from bundle at runtime.
    var displayName: String?

    var id: String { bundleIdentifier }

    init(bundleIdentifier: String, displayName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

// MARK: - Built-in bundle IDs

enum BuiltInMediaPlayerBundle {
    static let appleMusic = "com.apple.Music"
    static let spotify = "com.spotify.client"
    static let tidal = "com.tidal.desktop"
    static let deezer = "com.deezer.deezer-desktop"

    static let orderedDefaults: [String] = [
        appleMusic, spotify, tidal, deezer,
    ]

    static func defaultDisplayName(for bundleID: String) -> String {
        switch bundleID {
        case appleMusic: return "Apple Music"
        case spotify: return "Spotify"
        case tidal: return "Tidal"
        case deezer: return "Deezer"
        default:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return FileManager.default.displayName(atPath: url.path)
            }
            return bundleID
        }
    }

    /// Safari “Add to Dock” web apps use bundle IDs of this form.
    static func isSafariWebAppBundleID(_ id: String) -> Bool {
        id.hasPrefix("com.apple.Safari.WebApp.")
    }

    /// Media Remote often reports `com.apple.Safari` (or the Tech Preview) while audio is owned by a Web App process.
    static func isSafariShellNowPlayingBundleID(_ id: String) -> Bool {
        id == "com.apple.Safari" || id == "com.apple.SafariTechnologyPreview"
    }
}

// MARK: - Legacy migration

enum LegacyMediaKeysPriority: Int {
    case iTunes = 1
    case spotify = 2
    case tidal = 3
    case deezer = 4
}

extension PlayerTarget {
    /// Single-target list from pre–multi-target priority raw value (`0` or invalid → Apple Music, matching old `?? .iTunes`).
    static func migratedSingleTarget(fromLegacyRaw raw: Int) -> [PlayerTarget] {
        let legacy = LegacyMediaKeysPriority(rawValue: raw) ?? .iTunes
        let bid: String
        switch legacy {
        case .iTunes: bid = BuiltInMediaPlayerBundle.appleMusic
        case .spotify: bid = BuiltInMediaPlayerBundle.spotify
        case .tidal: bid = BuiltInMediaPlayerBundle.tidal
        case .deezer: bid = BuiltInMediaPlayerBundle.deezer
        }
        return [PlayerTarget(bundleIdentifier: bid, displayName: nil)]
    }
}
