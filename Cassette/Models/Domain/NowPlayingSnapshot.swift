// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    /// coverArtId from the source song — used by NowPlayingService to check
    /// ArtworkImageCache before falling back to a URL fetch.
    let coverArtId: String?
    /// True when the current playback is a live stream (radio). When true, duration and
    /// position are not meaningful — NowPlayingService omits them from the info dict so
    /// Control Center hides the scrubber automatically.
    let isLiveStream: Bool
    /// The radio station's display name when isLiveStream is true; nil otherwise.
    let radioStationName: String?
    /// Id of the playing song, so the remote like command knows what to star. `nil` for radio,
    /// which has nothing to favourite.
    let songId: String?
}
