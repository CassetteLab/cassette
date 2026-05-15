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
        print("[TRACE \(traceID)] load() start artistId=\(self.artistId)")
        isLoading = true
        error = nil
        let t0 = Date()
        do {
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] → libraryService.artist(id:)")
            print("[TRACE \(traceID)] → libraryService.artist(id:)")
            artist = try await libraryService.artist(id: artistId)
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← libraryService.artist done \(elapsed, privacy: .public)s")
            print("[TRACE \(traceID)] ← libraryService.artist done \(elapsed)s")
        } catch {
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← libraryService.artist FAILED \(elapsed, privacy: .public)s: \(error, privacy: .public)")
            print("[TRACE \(traceID)] ← libraryService.artist FAILED \(elapsed)s: \(error)")
            self.error = UserFacingError.from(error)
        }
        isLoading = false
        print("[TRACE \(traceID)] load() done total=\(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
        Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] load() done total=\(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s")
    }

    // Called from the view's .task after load() returns so artist loading and
    // index/network calls from similar artists never compete on the same server.
    func loadSimilarArtists() async {
        let traceID = String(UUID().uuidString.prefix(8))
        await loadSimilarArtists(traceID: traceID)
    }

    private func loadSimilarArtists(traceID: String) async {
        let t0 = Date()
        Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] → recommendationService.similarArtists(artistId=\(self.artistId, privacy: .public))")
        print("[TRACE \(traceID)] → recommendationService.similarArtists(artistId=\(self.artistId))")
        isLoadingSimilarArtists = true
        similarArtists = []
        defer { isLoadingSimilarArtists = false }
        do {
            similarArtists = try await recommendationService.similarArtists(to: artistId)
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← similarArtists done \(elapsed, privacy: .public)s count=\(self.similarArtists.count, privacy: .public)")
            print("[TRACE \(traceID)] ← similarArtists done \(elapsed)s count=\(self.similarArtists.count)")
        } catch {
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
            Logger.recommendations.notice("[TRACE \(traceID, privacy: .public)] ← similarArtists FAILED \(elapsed, privacy: .public)s: \(error, privacy: .public)")
            print("[TRACE \(traceID)] ← similarArtists FAILED \(elapsed)s: \(error)")
        }
    }
}
