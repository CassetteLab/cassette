// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// Device-local preference for cross-device playback continuation.
///
/// Lives outside the playback layer so the server layer can read it without depending on
/// `PlayerService`.
nonisolated enum PlaybackContinuationPreference {
    /// Kept device-local on purpose so each installation can opt in independently.
    static let userDefaultsKey = "cassette.playback.continuationEnabled"

    /// Opt-in. The feature writes the queue to the user's server on a timer, so it stays
    /// silent until the user asks for it.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: userDefaultsKey)
    }
}

/// What a server-saved queue means for this device — pure, so it can be tested without a player.
nonisolated enum PlaybackContinuationPlan {
    /// The queue this device should adopt.
    struct Plan: Sendable, Equatable {
        let songs: [DisplayableSong]
        let currentIndex: Int
        let position: TimeInterval

        var songIds: [String] { songs.map(\.id) }
    }

    /// Builds the plan, or returns `nil` when the remote queue brings nothing to adopt.
    ///
    /// `nil` covers two cases: an empty remote queue, and a remote queue this device already
    /// has. The second is also how we recognise **our own** upload. The obvious alternative —
    /// comparing `changedBy` — would need a per-installation client name, and the Subsonic `c=`
    /// parameter goes out on every request: Navidrome keys a player entry on (user, client), so
    /// a unique name per install means a permanent player entry per device *and* per reinstall,
    /// plus orphaned per-client transcoding profiles. Comparing the queue costs nothing and
    /// keeps `c=` a plain, fixed "Cassette".
    ///
    /// - Parameters:
    ///   - entries: songs of the remote queue, in order.
    ///   - current: id of the remote current song, if any.
    ///   - position: remote playback position in seconds.
    ///   - localQueueIds: ids currently queued on this device, in order.
    ///   - localCurrentId: id of the track this device is on, if any.
    static func make(
        entries: [Song],
        current: String?,
        position: TimeInterval?,
        localQueueIds: [String],
        localCurrentId: String?
    ) -> Plan? {
        let ids = entries.map(\.id)
        guard !ids.isEmpty else { return nil }
        guard ids != localQueueIds || current != localCurrentId else { return nil }

        // An unknown or absent `current` starts the queue from the top rather than refusing it.
        let index = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        return Plan(
            songs: entries.map { DisplayableSong(from: $0) },
            currentIndex: index,
            position: max(0, position ?? 0)
        )
    }

    static func make(
        from remote: SavedPlayQueue,
        localQueueIds: [String],
        localCurrentId: String?
    ) -> Plan? {
        make(
            entries: remote.entry,
            current: remote.current,
            position: remote.position,
            localQueueIds: localQueueIds,
            localCurrentId: localCurrentId
        )
    }
}
