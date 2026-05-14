// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

actor RecommendationService {
    private let providers: [any RecommendationProvider]

    init(providers: [any RecommendationProvider]) {
        self.providers = providers
    }

    func similarArtists(to artistID: String, limit: Int = 20) async throws -> [SimilarArtistRecommendation] {
        for provider in providers {
            let results = try await provider.similarArtists(toArtistID: artistID, limit: limit)
            if !results.isEmpty {
                Logger.recommendations.debug("similarArtists: \(results.count) result(s) from \(String(describing: type(of: provider)), privacy: .public)")
                return results
            }
        }
        Logger.recommendations.debug("similarArtists: all providers returned empty for artistID=\(artistID, privacy: .public)")
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
