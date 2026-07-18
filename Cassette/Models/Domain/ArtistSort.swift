// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// User-selectable ordering for the artists list. Persists via `@AppStorage("cassette.artistSort")`.
/// (ArtistID3 carries no date, so "recently added" isn't available without a different fetch — hence just
/// Name and Album Count.)
nonisolated enum ArtistSort: String, CaseIterable, Sendable {
    case name
    case albumCount

    var label: String {
        switch self {
        case .name: return "Name"
        case .albumCount: return "Album Count"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .albumCount: return "square.stack"
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
        }
    }

    private func key(_ artist: ArtistID3) -> String { artist.sortName ?? artist.name }
}
