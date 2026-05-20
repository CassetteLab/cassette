// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

actor RecommendationService {
    private let providers: [any RecommendationProvider]

    init(providers: [any RecommendationProvider]) {
        self.providers = providers
    }

    func similarArtists(to artistID: String, limit: Int = 20) async throws -> [SimilarArtistRecommendation] {
        Logger.recommendations.debug("[RS] similarArtists start artistID=\(artistID, privacy: .public) limit=\(limit, privacy: .public) providers=\(self.providers.count, privacy: .public)")
        for provider in providers {
            let providerName = String(describing: type(of: provider))
            let t0 = Date()
            Logger.recommendations.debug("[RS] → \(providerName, privacy: .public).similarArtists")
            let results = try await provider.similarArtists(toArtistID: artistID, limit: limit)
            let elapsed = Date().timeIntervalSince(t0)
            Logger.recommendations.debug("[RS] ← \(providerName, privacy: .public) returned \(results.count, privacy: .public) result(s) in \(String(format: "%.2f", elapsed), privacy: .public)s")
            if !results.isEmpty {
                return results
            }
        }
        Logger.recommendations.info("[RS] similarArtists: all providers empty artistID=\(artistID, privacy: .public)")
        return []
    }

    func freshReleases(limit: Int = 20, daysWindow: Int = 90) async throws -> [AlbumRecommendation] {
        for provider in providers {
            let results = try await provider.freshReleases(limit: limit, daysWindow: daysWindow)
            if !results.isEmpty {
                Logger.recommendations.debug("freshReleases: \(results.count) result(s) from \(String(describing: type(of: provider)), privacy: .public)")
                return results
            }
        }
        Logger.recommendations.debug("freshReleases: all providers returned empty")
        return []
    }
}
