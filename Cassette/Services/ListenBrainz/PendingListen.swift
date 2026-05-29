// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// One scrobble that failed to submit online and is waiting to be flushed.
/// Stored as a JSON array in Application Support — never in Documents or Caches.
/// Plain struct (no nonisolated) — actor-serialised by ListenBrainzService.
struct PendingListen: Codable, Sendable, Equatable {
    let listenedAt: Int
    let trackName: String
    let artistName: String
    let releaseName: String?
    /// Duration in milliseconds; included in the import payload for parity with live submits.
    /// Optional to handle legacy queue files written before this field was added.
    let durationMs: Int?
}
