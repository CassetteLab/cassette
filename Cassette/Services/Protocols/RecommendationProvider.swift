// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

protocol RecommendationProvider: Sendable {
    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation]
    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation]
}

extension RecommendationProvider {
    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] { [] }
    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] { [] }
}
