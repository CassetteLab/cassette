// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Sendable bridge from PlayerService to NowPlayingService.
/// Carries all metadata needed to update MPNowPlayingInfoCenter and load artwork.
nonisolated struct NowPlayingSnapshot: Sendable {
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let position: TimeInterval
    let playbackRate: Float
    let artworkURL: URL?
    let artworkHeaders: [String: String]
}
