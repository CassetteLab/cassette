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
        let traceID = String(UUID().uuidString.prefix(8))
        Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] load() start artistId=\(self.artistId, privacy: .public)")
        isLoading = true
        error = nil
        let t0 = Date()
        do {
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] → libraryService.artist(id:)")
            artist = try await libraryService.artist(id: artistId)
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← libraryService.artist done \(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s")
        } catch {
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← libraryService.artist FAILED \(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s: \(error, privacy: .public)")
            self.error = UserFacingError.from(error)
        }
        isLoading = false
        await loadSimilarArtists(traceID: traceID)
        Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] load() done total=\(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s")
    }

    private func loadSimilarArtists(traceID: String) async {
        let t0 = Date()
        Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] → recommendationService.similarArtists(artistId=\(self.artistId, privacy: .public))")
        isLoadingSimilarArtists = true
        similarArtists = []
        defer { isLoadingSimilarArtists = false }
        do {
            similarArtists = try await recommendationService.similarArtists(to: artistId)
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← similarArtists done \(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s count=\(self.similarArtists.count, privacy: .public)")
        } catch {
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← similarArtists FAILED \(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s: \(error, privacy: .public)")
        }
    }
}
