// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Manages MPNowPlayingInfoCenter and MPRemoteCommandCenter.
/// Active from v1: lockscreen, Control Center, AirPods, Apple Watch.
/// Designed as the direct extension point for CarPlay in v1.2 — no refactor needed.
protocol NowPlayingServiceProtocol: AnyObject, Sendable {
    /// Registers remote command handlers and begins observing PlayerState.
    func start() async

    /// Deregisters all handlers and clears now playing info.
    func stop() async

    /// Pushes a full metadata + artwork update (called from PlayerService on track change or seek).
    func update(with snapshot: NowPlayingSnapshot) async

    /// Merges elapsed time, rate, and duration into the existing nowPlayingInfo dict without
    /// touching title, artist, or artwork. Called on every periodic tick to prevent iOS
    /// extrapolation drift on the lock screen.
    func pushPosition(elapsed: TimeInterval, rate: Float, duration: TimeInterval) async
}
