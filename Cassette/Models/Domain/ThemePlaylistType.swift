// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum ThemePlaylistType: String, Codable, CaseIterable, Sendable {
    case mostPlayedMonth     = "most_played_month"
    case hiddenGems          = "hidden_gems"
    case forgottenFavorites  = "forgotten_favorites"
    case recentDiscoveries   = "recent_discoveries"

    var displayName: String {
        switch self {
        case .mostPlayedMonth:    "This Month's Favorites"
        case .hiddenGems:         "Hidden Gems"
        case .forgottenFavorites: "Forgotten Favorites"
        case .recentDiscoveries:  "Recent Discoveries"
        }
    }

    var systemImage: String {
        switch self {
        case .mostPlayedMonth:    "flame.fill"
        case .hiddenGems:         "sparkles"
        case .forgottenFavorites: "clock.arrow.circlepath"
        case .recentDiscoveries:  "star.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .mostPlayedMonth:    "Tracks you've played the most this month"
        case .hiddenGems:         "Tracks played less than 5 times but consistently loved"
        case .forgottenFavorites: "Tracks you loved but haven't played in 90+ days"
        case .recentDiscoveries:  "Tracks first played in the last 30 days"
        }
    }
}
