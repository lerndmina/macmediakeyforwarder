import AppKit
import Foundation

// MARK: - Command surface

/// Routes media commands to one concrete player implementation.
protocol MediaCommandHandler: AnyObject {
    var bundleIdentifier: String { get }
    var isRunning: Bool { get }
    /// `true` playing, `false` paused/stopped, `nil` if unknown (routing skips “playing” tie-break).
    var playbackIsLikelyPlaying: Bool? { get }

    func playPause()
    func nextTrack()
    func previousTrack()

    var supportsAppleMusicHoldBehavior: Bool { get }
    func backTrack()
    func fastForward()
    func rewind()
    func resume()
}

extension MediaCommandHandler {
    var supportsAppleMusicHoldBehavior: Bool { false }
    func backTrack() {}
    func fastForward() {}
    func rewind() {}
    func resume() {}
    var playbackIsLikelyPlaying: Bool? { nil }
}

// MARK: - Built-in adapters

private final class AppleMusicMediaHandler: MediaCommandHandler {
    let bundleIdentifier = BuiltInMediaPlayerBundle.appleMusic
    private let bridge: AppleMusicBridge
    init(bridge: AppleMusicBridge) { self.bridge = bridge }

    var isRunning: Bool { bridge.isRunning }
    var playbackIsLikelyPlaying: Bool? { bridge.playbackIsLikelyPlaying }
    var supportsAppleMusicHoldBehavior: Bool { true }

    func playPause() { bridge.playPause() }
    func nextTrack() { bridge.nextTrack() }
    func previousTrack() { bridge.backTrack() }
    func backTrack() { bridge.backTrack() }
    func fastForward() { bridge.fastForward() }
    func rewind() { bridge.rewind() }
    func resume() { bridge.resume() }
}

private final class SpotifyMediaHandler: MediaCommandHandler {
    let bundleIdentifier = BuiltInMediaPlayerBundle.spotify
    private let bridge: SpotifyBridge
    init(bridge: SpotifyBridge) { self.bridge = bridge }

    var isRunning: Bool { bridge.isRunning }
    var playbackIsLikelyPlaying: Bool? { bridge.playbackIsLikelyPlaying }

    func playPause() { bridge.playPause() }
    func nextTrack() { bridge.nextTrack() }
    func previousTrack() { bridge.previousTrack() }
}

private final class TidalMediaHandler: MediaCommandHandler {
    let bundleIdentifier = BuiltInMediaPlayerBundle.tidal
    private let bridge: TidalBridge
    init(bridge: TidalBridge) { self.bridge = bridge }

    var isRunning: Bool { bridge.isRunning }

    func playPause() { bridge.playPause() }
    func nextTrack() { bridge.nextTrack() }
    func previousTrack() { bridge.previousTrack() }
}

private final class DeezerMediaHandler: MediaCommandHandler {
    let bundleIdentifier = BuiltInMediaPlayerBundle.deezer
    private let bridge: DeezerBridge
    init(bridge: DeezerBridge) { self.bridge = bridge }

    var isRunning: Bool { bridge.isRunning }

    func playPause() { bridge.playPause() }
    func nextTrack() { bridge.nextTrack() }
    func previousTrack() { bridge.previousTrack() }
}

// MARK: - User-configured (non built-in): CGEvent to PID

/// Sends Space and Cmd+Left/Right to the process, matching [TidalBridge](MacMediaKeyForwarder/MediaControl/TidalBridge.swift) semantics for apps without AppleScript.
final class PIDKeyMediaHandler: MediaCommandHandler {

    let bundleIdentifier: String

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    private var app: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    var isRunning: Bool { app != nil }

    func playPause() { sendKey(code: 49) }
    func nextTrack() { sendKey(code: 124, flags: .maskCommand) }
    func previousTrack() { sendKey(code: 123, flags: .maskCommand) }

    private func sendKey(code: CGKeyCode, flags: CGEventFlags = []) {
        guard let pid = app?.processIdentifier else { return }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        if !flags.isEmpty {
            down?.flags = flags
            up?.flags = flags
        }
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}

// MARK: - Registry

/// Owns long-lived bridges and resolves a [MediaCommandHandler] for a bundle ID.
final class PlayerRuntime {

    private let appleMusic = AppleMusicBridge()
    private let spotify = SpotifyBridge()
    private let tidal = TidalBridge()
    private let deezer = DeezerBridge()

    private var pidKeyCache: [String: PIDKeyMediaHandler] = [:]

    private lazy var appleMusicHandler = AppleMusicMediaHandler(bridge: appleMusic)
    private lazy var spotifyHandler = SpotifyMediaHandler(bridge: spotify)
    private lazy var tidalHandler = TidalMediaHandler(bridge: tidal)
    private lazy var deezerHandler = DeezerMediaHandler(bridge: deezer)

    init() {}

    func connectDeferredPlayers() {
        deezer.connectIfRunning()
    }

    func handler(for bundleIdentifier: String) -> MediaCommandHandler {
        switch bundleIdentifier {
        case BuiltInMediaPlayerBundle.appleMusic: return appleMusicHandler
        case BuiltInMediaPlayerBundle.spotify: return spotifyHandler
        case BuiltInMediaPlayerBundle.tidal: return tidalHandler
        case BuiltInMediaPlayerBundle.deezer: return deezerHandler
        default:
            if pidKeyCache[bundleIdentifier] == nil {
                pidKeyCache[bundleIdentifier] = PIDKeyMediaHandler(bundleIdentifier: bundleIdentifier)
            }
            return pidKeyCache[bundleIdentifier]!
        }
    }

    /// Built-in bridges only (for Deezer startup side-effect).
    var deezerBridge: DeezerBridge { deezer }
}
