// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    /// Most-played songs (getTopSongs). Empty on bare self-hosted servers → the view hides the section.
    var topSongs: [DisplayableSong] = []
    /// Starts true so the section shows a skeleton until the first load resolves (then empty → hidden).
    var isLoadingTopSongs = true

    private let artistId: String
    private let libraryService: any LibraryServiceProtocol
    private let recommendationService: RecommendationService
    private let imageResolver: ExternalArtistImageResolver

    init(
        artistId: String,
        libraryService: any LibraryServiceProtocol,
        recommendationService: RecommendationService,
        imageResolver: ExternalArtistImageResolver
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

    /// Top songs (getTopSongs takes the artist NAME) — call after `load()` so `artist?.name` is set.
    func loadTopSongs() async {
        guard let name = artist?.name else { isLoadingTopSongs = false; return }
        isLoadingTopSongs = true
        defer { isLoadingTopSongs = false }
        do {
            topSongs = try await libraryService.topSongs(artist: name, count: 25)
        } catch {
            Logger.recommendations.warning("topSongs failed for \(self.artistId): \(error)")
            topSongs = []
        }
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
