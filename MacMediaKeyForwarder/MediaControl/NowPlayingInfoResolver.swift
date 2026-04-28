import AppKit
import Darwin
import Foundation

/// Best-effort “now playing” client bundle ID via private Media Remote APIs (optional).
///
/// Loads `MediaRemote.framework` with `dlopen` and resolves `MRMediaRemoteGetNowPlayingInfo` at runtime.
/// Also tries `MRMediaRemoteGetNowPlayingApplicationPID` when present so Dock Web Apps match their real bundle IDs.
final class NowPlayingInfoResolver {

    /// When nil, polling is disabled. When set, MR is only queried while `preferNowPlayingRouting` is true.
    weak var preferences: AppPreferences?

    private var frameworkHandle: UnsafeMutableRawPointer?
    private typealias MRGetNowPlayingBlock = @convention(block) (CFDictionary?) -> Void
    private typealias MRGetNowPlayingFn = @convention(c) (DispatchQueue, @escaping MRGetNowPlayingBlock) -> Void
    private typealias MRGetNowPlayingPIDBlock = @convention(block) (Int32) -> Void
    private typealias MRGetNowPlayingPIDFn = @convention(c) (DispatchQueue, @escaping MRGetNowPlayingPIDBlock) -> Void

    private var getNowPlayingInfo: MRGetNowPlayingFn?
    private var getNowPlayingApplicationPID: MRGetNowPlayingPIDFn?

    private let refreshQueue = DispatchQueue(label: "eu.meyer.mmkf.mediaremote", qos: .utility)
    private var timer: Timer?

    /// Called on the main queue when `lastNowPlayingBundleID` changes.
    var onNowPlayingBundleIDChanged: ((String?, String?) -> Void)?

    /// Latest bundle ID reported for the active Now Playing client (main-thread only).
    private(set) var lastNowPlayingBundleID: String?

    init() {
        loadSymbols()
    }

    deinit {
        stop()
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    func startPollingIfAvailable() {
        guard getNowPlayingInfo != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            self.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clearLastBundleID() {
        setLastNowPlayingBundleID(nil)
    }

    private func setLastNowPlayingBundleID(_ newValue: String?) {
        let old = lastNowPlayingBundleID
        guard old != newValue else { return }
        lastNowPlayingBundleID = newValue
        onNowPlayingBundleIDChanged?(old, newValue)
    }

    private func loadSymbols() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        frameworkHandle = handle
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(sym, to: MRGetNowPlayingFn.self)
        }
        let pidNames = [
            "MRMediaRemoteGetNowPlayingApplicationPID",
            "MRMediaRemoteGetNowPlayingClientPID",
        ]
        for name in pidNames {
            if let sym = dlsym(handle, name) {
                getNowPlayingApplicationPID = unsafeBitCast(sym, to: MRGetNowPlayingPIDFn.self)
                break
            }
        }
    }

    private func refresh() {
        guard preferences?.preferNowPlayingRouting == true else { return }
        guard let fn = getNowPlayingInfo else { return }

        fn(refreshQueue) { [weak self] cfDict in
            guard let self else { return }
            let dict = cfDict as? [String: Any]
            var bid = dict.flatMap { Self.extractBundleID(from: $0, depth: 0) }

            if bid == nil, let getPID = self.getNowPlayingApplicationPID {
                let dictBid = bid
                getPID(self.refreshQueue) { pid in
                    let fromPID: String? = {
                        guard pid > 0 else { return nil }
                        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                    }()
                    let resolved = dictBid ?? fromPID
                    DispatchQueue.main.async {
                        self.setLastNowPlayingBundleID(resolved)
                    }
                }
                return
            }

            DispatchQueue.main.async {
                self.setLastNowPlayingBundleID(bid)
            }
        }
    }

    private static func extractBundleID(from dict: [String: Any], depth: Int) -> String? {
        guard depth < 10 else { return nil }

        let directKeys = [
            "kMRMediaRemoteNowPlayingInfoOriginAppIdentifier",
            "kMRMediaRemoteNowPlayingInfoBundleIdentifier",
            "MRMediaRemoteNowPlayingInfoOriginAppIdentifier",
            "kMRMediaRemoteNowPlayingInfoDistributedBundleIdentifier",
            "kMRMediaRemoteNowPlayingInfoAppBundleIdentifier",
            "ClientBundleIdentifier",
            "ClientIdentifier",
        ]
        for k in directKeys {
            if let s = dict[k] as? String, looksLikeBundleIdentifier(s) { return s }
        }

        if let nested = dict["kMRMediaRemoteNowPlayingInfoClientProperties"] as? [String: Any] {
            if let inner = extractBundleID(from: nested, depth: depth + 1) { return inner }
        }

        for (_, value) in dict {
            if let sub = value as? [String: Any], let found = extractBundleID(from: sub, depth: depth + 1) {
                return found
            }
        }

        return nil
    }

    private static func looksLikeBundleIdentifier(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 7, s.count < 300, !s.contains(" "), s.contains(".") else { return false }
        let prefixes = ["com.", "app.", "net.", "eu.", "de.", "org."]
        return prefixes.contains { s.hasPrefix($0) }
    }
}
