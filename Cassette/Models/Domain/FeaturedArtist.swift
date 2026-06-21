// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// A frequently-appearing artist in a playlist, for the "Featured Artists" rail (Apple-Music direction).
///
/// Only artists with a non-nil `artistId` qualify — navigating to the artist detail reuses
/// `.cassetteNavigateToArtist`, which needs the id. (Real artist *photos* would require a `getArtist`
/// call; Phase 1 uses a representative track cover in the circle — flagged as a later refinement.)
struct FeaturedArtist: Identifiable, Hashable, Sendable {
    let id: String          // artistId — required (drives navigation)
    let name: String
    let coverArtId: String?  // a representative track cover for the circle

    /// Top artists by track count in the playlist, capped at `limit`. Ties break by first appearance.
    /// Tracks without an `artistId` (or with an empty name) are skipped — they can't be navigated to.
    static func from(_ songs: [DisplayableSong], limit: Int = 6) -> [FeaturedArtist] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var covers: [String: String?] = [:]
        for song in songs {
            guard let artistId = song.artistId,
                  let artist = song.artist, !artist.isEmpty else { continue }
            if counts[artistId] == nil {
                order.append(artistId)
                names[artistId] = artist
                covers[artistId] = song.coverArtId
            }
            counts[artistId, default: 0] += 1
        }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return order
            .sorted { lhs, rhs in
                let cl = counts[lhs] ?? 0, cr = counts[rhs] ?? 0
                if cl != cr { return cl > cr }
                return (rank[lhs] ?? 0) < (rank[rhs] ?? 0)
            }
            .prefix(limit)
            .map { FeaturedArtist(id: $0, name: names[$0] ?? "", coverArtId: covers[$0] ?? nil) }
    }
}
