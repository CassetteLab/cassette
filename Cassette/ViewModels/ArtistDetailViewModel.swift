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
    var outOfLibraryArtistImages: [String: URL?] = [:]

    private let artistId: String
    private let libraryService: any LibraryServiceProtocol
    private let recommendationService: RecommendationService
    private let imageResolver: ExternalArtistImageResolver

    init(
        artistId: String,
        libraryService: any LibraryServiceProtocol,
        recommendationService: RecommendationService,
        imageResolver: ExternalArtistImageResolver = ExternalArtistImageResolver()
    ) {
        self.artistId = artistId
        self.libraryService = libraryService
        self.recommendationService = recommendationService
        self.imageResolver = imageResolver
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
    }

    // Called from the view's .task after load() returns so artist loading and
    // index/network calls from similar artists never compete on the same server.
    func loadSimilarArtists() async {
        isLoadingSimilarArtists = true
        similarArtists = []
        defer { isLoadingSimilarArtists = false }
        do {
            similarArtists = try await recommendationService.similarArtists(to: artistId)
        } catch {
            Logger.recommendations.warning("similarArtists failed for \(self.artistId): \(error)")
        }
        Task { await loadOutOfLibraryImages() }
    }

    private func loadOutOfLibraryImages() async {
        for rec in similarArtists where !rec.inLibrary {
            let url = await imageResolver.resolveImageURL(for: rec)
            outOfLibraryArtistImages[rec.id] = url
        }
    }
}
