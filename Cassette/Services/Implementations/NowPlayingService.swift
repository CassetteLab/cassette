import Foundation
import MediaPlayer
import OSLog

/// Manages MPNowPlayingInfoCenter + MPRemoteCommandCenter.
/// Active from v1 (lockscreen, Control Center, AirPods, Apple Watch).
/// Architected as the direct extension point for CarPlay (v1.2) — no refactor needed.
actor NowPlayingService: NowPlayingServiceProtocol {
    private let playerService: any PlayerServiceProtocol
    private var observationTask: Task<Void, Never>?

    init(playerService: any PlayerServiceProtocol) {
        self.playerService = playerService
    }

    func start() async {
        // TODO: implement in Étape 4
        // - Register MPRemoteCommandCenter play/pause/next/prev/changePlaybackPosition handlers
        // - Observe playerService.state changes to push MPNowPlayingInfoCenter updates
        // - Start periodic position update timer
    }

    func stop() async {
        observationTask?.cancel()
        observationTask = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    func update(position: TimeInterval) async {
        // TODO: implement in Étape 4
    }
}
