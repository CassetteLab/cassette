// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import MediaPlayer
import OSLog

/// Manages MPNowPlayingInfoCenter + MPRemoteCommandCenter.
/// Active from v1 (lockscreen, Control Center, AirPods, Apple Watch).
/// Architected as the direct extension point for CarPlay (v1.2) — no refactor needed.
actor NowPlayingService: NowPlayingServiceProtocol {
    private let playerService: any PlayerServiceProtocol
    private let artworkLoader = ArtworkLoader()
    private let artworkImageCache: ArtworkImageCache
    private var commandsRegistered = false
    private var currentSong: NowPlayingSnapshot?

    init(playerService: any PlayerServiceProtocol, artworkImageCache: ArtworkImageCache) {
        self.playerService = playerService
        self.artworkImageCache = artworkImageCache
    }

    // MARK: - Lifecycle

    func start() async {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        RemoteCommandDebugLog.log("LIFE start() begin — registering all remote commands (cold start)")

        let playerService = playerService

        // Register EVERY command handler SYNCHRONOUSLY, on the MAIN THREAD, in ONE atomic block — before any
        // actor suspension and before the first now-playing info is set. MPRemoteCommandCenter is a main-thread
        // API: registering it from the NowPlayingService actor (off-main) let iOS snapshot setSupportedCommands
        // mid-registration — capturing only {Play, Pause} and NEVER re-snapshotting, which is why Next /
        // Previous / scrubber stayed greyed out (partial/random by run = the registration-vs-snapshot race).
        // One main-thread block guarantees the supported set is COMPLETE at iOS's single snapshot. addTarget is
        // what makes a command "supported"; isEnabled (in updateRemoteCommandsAvailability) only greys/ungreys
        // it afterwards — it never removes it from the set.
        await MainActor.run {
            let center = MPRemoteCommandCenter.shared()

            center.playCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    await playerService.resume()
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG playCommand")

            center.pauseCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    await playerService.pause()
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG pauseCommand")

            center.togglePlayPauseCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    await playerService.togglePlayPause()
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG togglePlayPauseCommand")

            center.nextTrackCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    do {
                        try await playerService.skipToNext()
                    } catch {
                        Logger.nowPlaying.error("[PLAYBACK] skipToNext failed: \(error, privacy: .public)")
                    }
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG nextTrackCommand")

            center.previousTrackCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    do {
                        try await playerService.skipToPrevious()
                    } catch {
                        Logger.nowPlaying.error("[PLAYBACK] skipToPrevious failed: \(error, privacy: .public)")
                    }
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG previousTrackCommand")

            #if os(macOS)
            // macOS Control Center may route the previous-track gesture through skipBackwardCommand
            // instead of previousTrackCommand. Register both so the gesture works on either path.
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 0)]
            center.skipBackwardCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    try? await playerService.skipToPrevious()
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG skipBackwardCommand (macOS)")
            #endif

            center.changePlaybackPositionCommand.addTarget { [playerService] event in
                guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                let position = seekEvent.positionTime
                Task.detached(priority: .userInitiated) {
                    await playerService.seek(to: position)
                }
                return .success
            }
            RemoteCommandDebugLog.log("REG changePlaybackPositionCommand")
            RemoteCommandDebugLog.log("EN start-end play=\(center.playCommand.isEnabled) pause=\(center.pauseCommand.isEnabled) toggle=\(center.togglePlayPauseCommand.isEnabled) next=\(center.nextTrackCommand.isEnabled) prev=\(center.previousTrackCommand.isEnabled) seek=\(center.changePlaybackPositionCommand.isEnabled)")
        }
        RemoteCommandDebugLog.log("LIFE start() done — all commands registered on main thread")
    }

    func stop() async {
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            RemoteCommandDebugLog.log("INFO clear (stop) — nowPlayingInfo=nil")
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            #endif
        }
        #if os(macOS)
        postDiscordRPC(.stopped)
        #endif
    }

    // MARK: - Update

    func update(with snapshot: NowPlayingSnapshot) async {
        RemoteCommandDebugLog.log("STATE update entry live=\(snapshot.isLiveStream) artURL=\(snapshot.artworkURL != nil) coverId=\(snapshot.coverArtId != nil) rate=\(snapshot.playbackRate) pos=\(snapshot.position) dur=\(snapshot.duration)")
        if snapshot.isLiveStream {
            // Live stream: fresh dict with the IsLiveStream flag set.
            // Duration and elapsed time are intentionally omitted — Control Center hides
            // the scrubber automatically when MPNowPlayingInfoPropertyIsLiveStream is true.
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: snapshot.title,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
                MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
            ]
            if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
            let baseInfo = info
            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo
                RemoteCommandDebugLog.log("INFO set live-base keys=[\(npKeySummary(baseInfo))]")
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = .playing
                #endif
            }
            #if os(macOS)
            postDiscordRPC(.nowPlaying(.init(
                title: snapshot.title,
                artist: snapshot.artist ?? "",
                album: snapshot.album ?? "",
                duration: snapshot.duration,
                startedAt: Date().timeIntervalSince1970
            )))
            #endif

            // Check ArtworkImageCache — use hero tier for lock screen / Control Center quality.
            if let coverArtId = snapshot.coverArtId,
               let cachedImage = await artworkImageCache.cached(for: coverArtId, tier: .hero) {
                let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
                await MainActor.run {
                    var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
                    infoWithArt[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                    RemoteCommandDebugLog.log("INFO set live-artwork keys=[\(npKeySummary(infoWithArt))]")
                    #if os(macOS)
                    MPNowPlayingInfoCenter.default().playbackState = .playing
                    #endif
                }
            }

            updateRemoteCommandsAvailability(isLiveStream: true)
            return
        }

        updateRemoteCommandsAvailability(isLiveStream: false)

        if snapshot.artworkURL == nil {
            // Position-only update (pause/resume/seek): merge into the existing dict so
            // artwork already loaded for the current track is preserved.
            await MainActor.run {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyTitle] = snapshot.title
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
                info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
                info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.playbackRate
                info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
                if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                RemoteCommandDebugLog.log("INFO set position-only keys=[\(npKeySummary(info))]")
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
                #endif
            }
            #if os(macOS)
            if snapshot.playbackRate == 0 {
                postDiscordRPC(.stopped)
            } else if let song = currentSong {
                postDiscordRPC(.nowPlaying(.init(
                    title: song.title,
                    artist: song.artist ?? "",
                    album: song.album ?? "",
                    duration: song.duration,
                    startedAt: Date().timeIntervalSince1970
                )))
            }
            #endif
            return
        }

        // New track: build from scratch so stale artwork from the previous track is cleared
        // before the new one loads. Text metadata is committed first so the lockscreen
        // doesn't flash empty while the artwork fetch is in progress.
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
        currentSong = snapshot
        let baseInfo = info
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo
            RemoteCommandDebugLog.log("INFO set newtrack-base keys=[\(npKeySummary(baseInfo))]")
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
            #endif
        }
        #if os(macOS)
        postDiscordRPC(.nowPlaying(.init(
            title: snapshot.title,
            artist: snapshot.artist ?? "",
            album: snapshot.album ?? "",
            duration: snapshot.duration,
            startedAt: Date().timeIntervalSince1970
        )))
        #endif

        // Fast path: image already in ArtworkImageCache (pre-loaded when the card was visible).
        if let coverArtId = snapshot.coverArtId,
           let cachedImage = await artworkImageCache.cached(for: coverArtId, tier: .hero) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                RemoteCommandDebugLog.log("INFO set newtrack-artwork-fast keys=[\(npKeySummary(infoWithArt))]")
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
                #endif
            }
            return
        }

        // Slow path: fetch from URL and populate both caches.
        if let artworkURL = snapshot.artworkURL,
           let artwork = await artworkLoader.artwork(for: artworkURL, headers: snapshot.artworkHeaders) {
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                RemoteCommandDebugLog.log("INFO set newtrack-artwork-slow keys=[\(npKeySummary(infoWithArt))]")
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
                #endif
            }
        }
    }

    // MARK: - Periodic position push

    func pushPosition(elapsed: TimeInterval, rate: Float, duration: TimeInterval) async {
        guard elapsed >= 0, duration > 0, elapsed <= duration else { return }
        await MainActor.run {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPNowPlayingInfoPropertyPlaybackRate] = rate
            info[MPMediaItemPropertyPlaybackDuration] = duration
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            RemoteCommandDebugLog.log("INFO set pushPosition keys=[\(npKeySummary(info))]")
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = .playing
            #endif
        }
    }

    // MARK: - Remote command availability

    private func updateRemoteCommandsAvailability(isLiveStream: Bool) {
        let center = MPRemoteCommandCenter.shared()
        // Skip, previous, and scrubbing are meaningless for a live stream.
        // play/pause/togglePlayPause remain enabled in both modes (always-on).
        Logger.nowPlaying.debug("[REMOTE] updateRemoteCommandsAvailability — isLiveStream=\(isLiveStream, privacy: .public) nextEnabled=\(!isLiveStream, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] nextTrackCommand.isEnabled BEFORE=\(center.nextTrackCommand.isEnabled, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] previousTrackCommand.isEnabled BEFORE=\(center.previousTrackCommand.isEnabled, privacy: .public)")
        RemoteCommandDebugLog.log("EN updateAvail call isLiveStream=\(isLiveStream)")
        RemoteCommandDebugLog.log("EN BEFORE play=\(center.playCommand.isEnabled) pause=\(center.pauseCommand.isEnabled) toggle=\(center.togglePlayPauseCommand.isEnabled) next=\(center.nextTrackCommand.isEnabled) prev=\(center.previousTrackCommand.isEnabled) seek=\(center.changePlaybackPositionCommand.isEnabled)")
        center.nextTrackCommand.isEnabled = !isLiveStream
        center.previousTrackCommand.isEnabled = !isLiveStream
        #if os(macOS)
        center.skipBackwardCommand.isEnabled = !isLiveStream
        #endif
        center.changePlaybackPositionCommand.isEnabled = !isLiveStream
        Logger.nowPlaying.debug("[REMOTE] nextTrackCommand.isEnabled AFTER=\(center.nextTrackCommand.isEnabled, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] previousTrackCommand.isEnabled AFTER=\(center.previousTrackCommand.isEnabled, privacy: .public)")
        RemoteCommandDebugLog.log("EN AFTER play=\(center.playCommand.isEnabled) pause=\(center.pauseCommand.isEnabled) toggle=\(center.togglePlayPauseCommand.isEnabled) next=\(center.nextTrackCommand.isEnabled) prev=\(center.previousTrackCommand.isEnabled) seek=\(center.changePlaybackPositionCommand.isEnabled)")
    }

    // MARK: - Discord RPC

    #if os(macOS)
    private nonisolated func postDiscordRPC(_ event: DiscordRPCEvent) {
        let port = 47832
        let urlString: String
        var body: Data?

        switch event {
        case .nowPlaying(let info):
            urlString = "http://localhost:\(port)/now-playing"
            body = try? JSONEncoder().encode(info)
        case .stopped:
            urlString = "http://localhost:\(port)/playback-stopped"
        }

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
    #endif

}

/// Compact, privacy-safe summary of WHICH now-playing keys are present (names only, never the values) — a
/// missing key here maps directly to a missing control on iOS, so this is the core signal for the "partial
/// controls" symptom. Free function so it's callable inside `MainActor.run` blocks with no actor hop.
private func npKeySummary(_ info: [String: Any]) -> String {
    var present: [String] = []
    if info[MPMediaItemPropertyTitle] != nil { present.append("title") }
    if info[MPMediaItemPropertyArtist] != nil { present.append("artist") }
    if info[MPMediaItemPropertyAlbumTitle] != nil { present.append("album") }
    if info[MPMediaItemPropertyPlaybackDuration] != nil { present.append("dur") }
    if info[MPNowPlayingInfoPropertyElapsedPlaybackTime] != nil { present.append("elapsed") }
    if info[MPNowPlayingInfoPropertyPlaybackRate] != nil { present.append("rate") }
    if info[MPMediaItemPropertyArtwork] != nil { present.append("art") }
    if info[MPNowPlayingInfoPropertyIsLiveStream] != nil { present.append("live") }
    return present.joined(separator: ",")
}

/// Opt-in, size-capped, off-actor file logger for the MPRemoteCommandCenter skip/previous diagnostic.
///
/// This is the active diagnostic for the remote-command (next/previous) bug, so the capability is kept —
/// but made safe. It is OFF by default and enabled at runtime via the UserDefaults flag `debug.rccFileLog`
/// (so it can be turned on for a release build on a real device, unlike a `#if DEBUG` gate). When enabled it
/// appends on a background serial queue — never blocking the playback actor — and rotates the file at a size
/// cap so `cassette_debug.log` can never grow unbounded.
enum RemoteCommandDebugLog {
    /// Runtime toggle, default OFF. Set this UserDefaults bool to true to capture the log while diagnosing.
    nonisolated static let enabledKey = "debug.rccFileLog"
    /// Rotate when the active log reaches this size; total on disk is bounded to ~2x this (.log + .log.1).
    private nonisolated static let maxBytes = 256 * 1024
    private nonisolated static let queue = DispatchQueue(label: "fr.mathieu-dubart.cassette.rcc-debug-log", qos: .utility)

    /// `@autoclosure` so that when disabled (the default) NOTHING is built — the caller pays only a single bool
    /// read, so the hot path (periodic position pushes) and the observed timing stay unperturbed (no Heisenbug
    /// — that's the #1 trap when instrumenting a race). The monotonic `uptimeNanoseconds` + thread tag are
    /// captured SYNCHRONOUSLY in the caller's context, so they record the EVENT's true time/thread, not the
    /// background writer's. Monotonic ns orders two events inside the same wall-clock millisecond — that
    /// ordering is exactly what reveals which of registration / enable / nowPlayingInfo / setActive wins the race.
    nonisolated static func log(_ message: @autoclosure () -> String) {
        #if os(iOS)
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let mono = DispatchTime.now().uptimeNanoseconds
        let thr = Thread.isMainThread ? "main" : "t\(pthread_mach_thread_np(pthread_self()))"
        let line = "[RCC] mono=\(mono) thr=\(thr) \(Date()) \(message())\n"
        queue.async {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
                  let data = line.data(using: .utf8) else { return }
            let file = docs.appendingPathComponent("cassette_debug.log")
            // Rotate before appending once at/over the cap so the file can't grow without bound.
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int, size >= maxBytes {
                let rotated = docs.appendingPathComponent("cassette_debug.log.1")
                try? fm.removeItem(at: rotated)
                try? fm.moveItem(at: file, to: rotated)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: file)
            }
        }
        #endif
    }
}

#if os(macOS)
private nonisolated enum DiscordRPCEvent {
    case nowPlaying(DiscordNowPlayingInfo)
    case stopped
}

private nonisolated struct DiscordNowPlayingInfo: Encodable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let startedAt: Double
}
#endif
