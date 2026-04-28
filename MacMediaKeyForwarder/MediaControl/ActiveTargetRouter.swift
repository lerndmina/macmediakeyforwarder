import Foundation

/// Picks which whitelisted bundle should receive the next media command.
enum ActiveTargetRouter {

    /// Returns the handler for the active target, or `nil` if the whitelist is empty.
    static func activeHandler(
        preferences: AppPreferences,
        runtime: PlayerRuntime,
        nowPlayingBundleID: String?
    ) -> MediaCommandHandler? {
        let ids = preferences.targetBundleIdentifiers
        guard !ids.isEmpty else { return nil }

        if preferences.preferNowPlayingRouting, let np = nowPlayingBundleID {
            if ids.contains(np) {
                return runtime.handler(for: np)
            }
            // MR often reports `com.apple.Safari` while the audible client is a Dock Web App (`com.apple.Safari.WebApp.*`).
            if BuiltInMediaPlayerBundle.isSafariShellNowPlayingBundleID(np) {
                for id in ids where BuiltInMediaPlayerBundle.isSafariWebAppBundleID(id) {
                    if runtime.handler(for: id).isRunning {
                        return runtime.handler(for: id)
                    }
                }
            }
        }

        for id in ids {
            let h = runtime.handler(for: id)
            if h.playbackIsLikelyPlaying == true {
                return h
            }
        }

        for id in ids {
            let h = runtime.handler(for: id)
            if h.isRunning {
                return h
            }
        }

        return runtime.handler(for: ids[0])
    }

    static func anyListedPlayerRunning(preferences: AppPreferences, runtime: PlayerRuntime) -> Bool {
        preferences.targetBundleIdentifiers.contains { runtime.handler(for: $0).isRunning }
    }
}
