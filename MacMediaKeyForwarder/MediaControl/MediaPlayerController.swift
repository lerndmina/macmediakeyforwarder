import Foundation

/// Routes media key events to the appropriate player based on whitelist order,
/// optional Now Playing routing, pause state, and “last app you drove with media keys”.
final class MediaPlayerController {

    let preferences: AppPreferences
    private let runtime = PlayerRuntime()
    private let nowPlaying = NowPlayingInfoResolver()

    private var keyHoldMachine = KeyHoldStateMachine()
    private var preferNowPlayingObserver: NSObjectProtocol?

    /// Last app that received a forwarded media command (play / pause / skip). Used so **Play** resumes that app until Now Playing shows another whitelisted client (manual playback elsewhere).
    private var lastMediaKeyActedBundleID: String?

    /// Suppresses duplicate `isPressed` events for the play key (hardware / Bluetooth often sends repeats without a release).
    private var playKeyDownLatch = false

    /// Debounced clear of `lastMediaKeyActedBundleID` when MR shows a different whitelisted app.
    private var stickyClearWorkItem: DispatchWorkItem?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        runtime.connectDeferredPlayers()
        nowPlaying.preferences = preferences
        nowPlaying.onNowPlayingBundleIDChanged = { [weak self] old, new in
            self?.handleNowPlayingBundleChanged(from: old, to: new)
        }
        syncNowPlayingPolling()
        preferNowPlayingObserver = NotificationCenter.default.addObserver(
            forName: .mmkfPreferNowPlayingRoutingChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncNowPlayingPolling()
        }
    }

    deinit {
        stickyClearWorkItem?.cancel()
        if let preferNowPlayingObserver {
            NotificationCenter.default.removeObserver(preferNowPlayingObserver)
        }
    }

    private func syncNowPlayingPolling() {
        if preferences.preferNowPlayingRouting {
            nowPlaying.startPollingIfAvailable()
        } else {
            nowPlaying.stop()
            nowPlaying.clearLastBundleID()
        }
    }

    // MARK: - Sticky target + MR

    private func handleNowPlayingBundleChanged(from _: String?, to new: String?) {
        guard let sticky = lastMediaKeyActedBundleID else { return }
        guard let new, new != sticky else { return }
        guard preferences.targetBundleIdentifiers.contains(new) else { return }

        stickyClearWorkItem?.cancel()
        let captured = new
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.nowPlaying.lastNowPlayingBundleID == captured else { return }
            self.lastMediaKeyActedBundleID = nil
        }
        stickyClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func recordLastMediaKeyTarget(_ bundleID: String) {
        lastMediaKeyActedBundleID = bundleID
    }

    /// Normal routing (MR + list + playing + running).
    private func activeHandler() -> MediaCommandHandler? {
        ActiveTargetRouter.activeHandler(
            preferences: preferences,
            runtime: runtime,
            nowPlayingBundleID: nowPlaying.lastNowPlayingBundleID
        )
    }

    /// For **Play** only: prefer the last app we controlled until MR shows another whitelisted client (debounced).
    private func handlerForPlayKeyDown() -> MediaCommandHandler? {
        if let sticky = lastMediaKeyActedBundleID,
           preferences.targetBundleIdentifiers.contains(sticky),
           runtime.handler(for: sticky).isRunning {
            return runtime.handler(for: sticky)
        }
        return activeHandler()
    }

    private func handlerForKeyDown(_ event: MediaKeyEvent) -> MediaCommandHandler? {
        if event.keyCode == .play {
            return handlerForPlayKeyDown()
        }
        return activeHandler()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: MediaKeyEvent) {
        if preferences.pauseMode == .paused {
            return
        }

        if preferences.pauseMode == .automatic {
            if !ActiveTargetRouter.anyListedPlayerRunning(preferences: preferences, runtime: runtime) {
                return
            }
        }

        if event.keyCode == .play, !event.isPressed {
            playKeyDownLatch = false
        }

        if event.isPressed {
            handleKeyDown(event)
        } else {
            handleKeyUp(event)
        }
    }

    // MARK: - Key Down

    private func handleKeyDown(_ event: MediaKeyEvent) {
        if event.keyCode == .play, playKeyDownLatch {
            return
        }

        guard let handler = handlerForKeyDown(event) else { return }

        if event.keyCode == .play {
            playKeyDownLatch = true
        }

        if handler.supportsAppleMusicHoldBehavior,
           handler.bundleIdentifier == BuiltInMediaPlayerBundle.appleMusic {
            handleAppleMusicPriorityKeyDown(event, handler: handler)
            return
        }

        switch event.keyCode {
        case .play:
            handler.playPause()
            recordLastMediaKeyTarget(handler.bundleIdentifier)
        case .next, .fast:
            handler.nextTrack()
            recordLastMediaKeyTarget(handler.bundleIdentifier)
        case .previous, .rewind:
            handler.previousTrack()
            recordLastMediaKeyTarget(handler.bundleIdentifier)
        }
    }

    private func handleAppleMusicPriorityKeyDown(_ event: MediaKeyEvent, handler: MediaCommandHandler) {
        switch event.keyCode {
        case .play:
            handler.playPause()
            recordLastMediaKeyTarget(handler.bundleIdentifier)

        case .next, .fast, .previous, .rewind:
            let action = keyHoldMachine.keyDown()
            switch action {
            case .startHolding:
                if event.keyCode.isForward {
                    handler.fastForward()
                } else {
                    handler.rewind()
                }
                recordLastMediaKeyTarget(handler.bundleIdentifier)
            case .startWaiting, .none, .shortRelease, .holdRelease:
                break
            }
        }
    }

    // MARK: - Key Up

    private func handleKeyUp(_ event: MediaKeyEvent) {
        let action = keyHoldMachine.keyUp()

        switch action {
        case .shortRelease:
            guard let handler = activeHandler(),
                  handler.supportsAppleMusicHoldBehavior,
                  handler.bundleIdentifier == BuiltInMediaPlayerBundle.appleMusic else { return }
            if event.keyCode.isForward {
                handler.nextTrack()
            } else if event.keyCode.isBackward {
                handler.backTrack()
            }
            recordLastMediaKeyTarget(handler.bundleIdentifier)

        case .holdRelease:
            guard let handler = activeHandler(),
                  handler.supportsAppleMusicHoldBehavior,
                  handler.bundleIdentifier == BuiltInMediaPlayerBundle.appleMusic else { return }
            handler.resume()
            recordLastMediaKeyTarget(handler.bundleIdentifier)

        case .startWaiting, .startHolding, .none:
            break
        }
    }
}
