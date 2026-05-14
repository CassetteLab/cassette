// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

actor SubsonicRecommendationProvider: RecommendationProvider {
    private let serverService: any ServerServiceProtocol
    private var cachedClient: SwiftSonicClient?
    private var cachedServerId: UUID?

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    private func client() async throws -> SwiftSonicClient {
        let activeId = await MainActor.run { serverService.state.activeServer?.id }
        if let cached = cachedClient, cachedServerId == activeId, activeId != nil {
            return cached
        }
        let fresh = try await serverService.makeSwiftSonicClient()
        cachedClient = fresh
        cachedServerId = activeId
        return fresh
    }

    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] {
        let info = try await client().getArtistInfo2(id: toArtistID, count: limit)
        return (info.similarArtist ?? []).prefix(limit).map {
            SimilarArtistRecommendation(id: $0.id, name: $0.name, coverArt: $0.coverArt, inLibrary: true, mbid: $0.musicBrainzId)
        }
    }

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        []
    }
}
