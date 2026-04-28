import Cocoa
import ScriptingBridge

// MARK: - ScriptingBridge Protocol

@objc private protocol MusicApplication {
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func backTrack()
    @objc optional func fastForward()
    @objc optional func rewind()
    @objc optional func resume()
}

extension SBApplication: MusicApplication {}

// MARK: - Apple Music Bridge

/// ScriptingBridge wrapper for Apple Music (com.apple.Music).
final class AppleMusicBridge {

    private static let bundleID = "com.apple.Music"

    private lazy var app: (any MusicApplication)? = {
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

    func backTrack() {
        app?.backTrack?()
    }

    func fastForward() {
        app?.fastForward?()
    }

    func rewind() {
        app?.rewind?()
    }

    func resume() {
        app?.resume?()
    }

    /// `kPSP` / `playing` from Music’s scripting object (`nil` if unknown).
    var playbackIsLikelyPlaying: Bool? {
        guard isRunning else { return false }
        guard let raw = (app as AnyObject?)?.value(forKey: "playerState") else { return nil }
        let code: UInt32?
        if let u = raw as? UInt32 { code = u }
        else if let i = raw as? Int { code = UInt32(bitPattern: Int32(i)) }
        else { return nil }
        return code == Self.playingFourCC
    }

    /// Music / Spotify-style `playing` state code (`kPSP`).
    private static let playingFourCC: UInt32 = 0x6B505350
}
