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

    /// Server-provided biography (getArtistInfo). nil/empty on bare servers → section hidden.
    var biography: String?
    /// Last.fm link from getArtistInfo, when the server returns one.
    var lastFmURL: URL?
    /// Starts true so the bio area shows a 3-line skeleton until getArtistInfo resolves (then the bio
    /// fades in, or the area collapses if the server has none).
    var isLoadingArtistInfo = true

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

    /// Biography and Last.fm link from getArtistInfo. Independent of similar artists,
    /// which come from `recommendationService`. Slow external lookups are already
    /// guarded by the service's 15s timeout, so this loads in the background.
    func loadArtistInfo() async {
        defer { isLoadingArtistInfo = false }
        do {
            let info = try await libraryService.getArtistInfo(forArtistID: artistId, count: 20)
            let cleaned = info.biography?.strippingArtistBioMarkup
            biography = (cleaned?.isEmpty ?? true) ? nil : cleaned
            lastFmURL = info.lastFmUrl.flatMap(URL.init(string:))
        } catch {
            Logger.recommendations.warning("artistInfo failed for \(self.artistId): \(error)")
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

private extension String {
    /// Turns a Last.fm/MusicBrainz biography into plain text: drops HTML tags and the
    /// trailing "Read more on Last.fm" link that Subsonic servers pass through verbatim.
    var strippingArtistBioMarkup: String {
        var text = self

        // Cut the Last.fm read-more tail (everything from the last <a ...>Read more…</a>)
        if let range = text.range(of: "<a", options: .backwards),
           text[range.lowerBound...].localizedCaseInsensitiveContains("last.fm") {
            text = String(text[..<range.lowerBound])
        }

        // Strip remaining tags and decode the few entities Last.fm emits
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&apos;": "'"] {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
