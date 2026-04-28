import Cocoa
import ScriptingBridge

// MARK: - ScriptingBridge Protocol

@objc private protocol SpotifyApplication {
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
}

extension SBApplication: SpotifyApplication {}

// MARK: - Spotify Bridge

/// ScriptingBridge wrapper for Spotify (com.spotify.client).
final class SpotifyBridge {

    private static let bundleID = "com.spotify.client"

    private lazy var app: (any SpotifyApplication)? = {
        SBApplication(bundleIdentifier: Self.bundleID)
    }()

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.bundleID
        }
    }

    func playPause() {
        app?.playpause?()
    }

    func nextTrack() {
        app?.nextTrack?()
    }

    func previousTrack() {
        app?.previousTrack?()
    }

    /// Spotify `player state` playing (`kPSP`); `nil` if unknown.
    var playbackIsLikelyPlaying: Bool? {
        guard isRunning else { return false }
        guard let raw = (app as AnyObject?)?.value(forKey: "playerState") else { return nil }
        let code: UInt32?
        if let u = raw as? UInt32 { code = u }
        else if let i = raw as? Int { code = UInt32(bitPattern: Int32(i)) }
        else { return nil }
        return code == Self.playingFourCC
    }

    private static let playingFourCC: UInt32 = 0x6B505350
}
