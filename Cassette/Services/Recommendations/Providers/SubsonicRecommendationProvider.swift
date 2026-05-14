// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

actor SubsonicRecommendationProvider: RecommendationProvider {
    private let libraryService: any LibraryServiceProtocol

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] {
        let info = try await libraryService.getArtistInfo(forArtistID: toArtistID, count: limit)
        let similar = (info.similarArtist ?? []).prefix(limit)
        var results: [SimilarArtistRecommendation] = []
        results.reserveCapacity(similar.count)
        for s in similar {
            let inLibrary = await libraryService.findArtist(byName: s.name) != nil
            results.append(SimilarArtistRecommendation(
                id: s.id,
                name: s.name,
                coverArt: s.coverArt,
                inLibrary: inLibrary,
                mbid: s.musicBrainzId
            ))
        }
        Logger.recommendations.debug("[SUBSONIC] similarArtists: \(results.count, privacy: .public) results (\(results.filter { $0.inLibrary }.count, privacy: .public) in library) for artistId=\(toArtistID, privacy: .public)")
        return results
    }

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        []
    }
}
