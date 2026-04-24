import Foundation

/// Manages MPNowPlayingInfoCenter and MPRemoteCommandCenter.
/// Active from v1: lockscreen, Control Center, AirPods, Apple Watch.
/// Designed as the direct extension point for CarPlay in v1.2 — no refactor needed.
protocol NowPlayingServiceProtocol: AnyObject, Sendable {
    /// Registers remote command handlers and begins observing PlayerState.
    func start() async

    /// Deregisters all handlers and clears now playing info.
    func stop() async

    /// Pushes an updated playback position (called on scrub or periodic timer tick).
    func update(position: TimeInterval) async
}
