// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

@Observable
@MainActor
final class ArtistDetailViewModel {
    var artist: ArtistID3?
    var isLoading = false
    var isPlayLoading = false
    var error: UserFacingError?
    var similarArtists: [SimilarArtistRecommendation] = []
    var isLoadingSimilarArtists = false

    private let artistId: String
    private let libraryService: any LibraryServiceProtocol
    private let recommendationService: RecommendationService

    init(artistId: String, libraryService: any LibraryServiceProtocol, recommendationService: RecommendationService) {
        self.artistId = artistId
        self.libraryService = libraryService
        self.recommendationService = recommendationService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            artist = try await libraryService.artist(id: artistId)
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
        await loadSimilarArtists()
    }

    private func loadSimilarArtists() async {
        isLoadingSimilarArtists = true
        similarArtists = []
        defer { isLoadingSimilarArtists = false }
        do {
            similarArtists = try await recommendationService.similarArtists(to: artistId)
        } catch {
            Logger.recommendations.debug("similarArtists load failed for artistId=\(self.artistId, privacy: .public): \(error, privacy: .public)")
        }
    }
}
