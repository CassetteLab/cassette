// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated struct SimilarArtistRecommendation: Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let coverArt: String?
    let inLibrary: Bool
    /// MusicBrainz ID, present for LB-sourced results. nil for Subsonic-only results.
    let mbid: String?
}
