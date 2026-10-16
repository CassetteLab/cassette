// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// User-selectable ordering for the artists list. Persists via `@AppStorage("cassette.artistSort")`.
/// (ArtistID3 carries no creation date, so "recently added" isn't available without a different fetch.)
nonisolated enum ArtistSort: String, CaseIterable, Sendable {
    case name
    case albumCount
    case starred
    case rating

    /// Shown in the sort menus. `String(localized:)` and not a bare literal: the menus pass this
    /// through as a `String`, which SwiftUI does not localize on its own.
    var label: String {
        switch self {
        case .name: return String(localized: "Name")
        case .albumCount: return String(localized: "Album Count")
        case .starred: return String(localized: "Starred")
        case .rating: return String(localized: "Rating")
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .albumCount: return "square.stack"
        case .starred: return "star"
        case .rating: return "star.leadinghalf.filled"
        }
    }

    func sorted(_ artists: [ArtistID3]) -> [ArtistID3] {
        switch self {
        case .name:
            return artists.sorted { key($0).localizedStandardCompare(key($1)) == .orderedAscending }
        case .albumCount:
            return artists.sorted {
                let a = $0.albumCount ?? 0, b = $1.albumCount ?? 0
                if a != b { return a > b } // most albums first
                return key($0).localizedStandardCompare(key($1)) == .orderedAscending
            }
        case .starred:
            // Starred artists first, most recently starred at the top.
            return artists.sorted {
                let a = $0.starred ?? .distantPast, b = $1.starred ?? .distantPast
                if a != b { return a > b }
                return key($0).localizedStandardCompare(key($1)) == .orderedAscending
            }
        case .rating:
            return artists.sorted {
                let a = $0.userRating ?? 0, b = $1.userRating ?? 0
                if a != b { return a > b }
                return key($0).localizedStandardCompare(key($1)) == .orderedAscending
            }
        }
    }

    private func key(_ artist: ArtistID3) -> String { artist.sortName ?? artist.name }
}
