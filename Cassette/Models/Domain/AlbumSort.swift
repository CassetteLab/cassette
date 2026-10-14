// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// User-selectable ordering for album collections, shared by the artist discography and the global album
/// list. String-backed so it persists via `@AppStorage("cassette.albumSort")`. Sorting is client-side on an
/// already-fetched array, so a single ordering works identically everywhere.
nonisolated enum AlbumSort: String, CaseIterable, Sendable {
    case recentlyAdded
    case releaseYear
    case name
    case artist
    case mostPlayed
    case recentlyPlayed
    case genre
    case starred
    case rating

    var label: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .releaseYear: return "Release Year"
        case .name: return "Name"
        case .artist: return "Artist"
        case .mostPlayed: return "Most Played"
        case .recentlyPlayed: return "Recently Played"
        case .genre: return "Genre"
        case .starred: return "Starred"
        case .rating: return "Rating"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyAdded: return "clock"
        case .releaseYear: return "calendar"
        case .name: return "textformat"
        case .artist: return "music.mic"
        case .mostPlayed: return "chart.bar"
        case .recentlyPlayed: return "play.circle"
        case .genre: return "tag"
        case .starred: return "star"
        case .rating: return "star.leadinghalf.filled"
        }
    }

    /// Orders an already-fetched album array. Missing fields (no `created`, no `year`, no `artist`, ...) sort
    /// last. The orderings added after the first three break ties by album name so the result is stable.
    func sorted(_ albums: [AlbumID3]) -> [AlbumID3] {
        switch self {
        case .recentlyAdded:
            return albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .releaseYear:
            return albums.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
        case .name:
            return albums.sorted { sortKey($0).localizedStandardCompare(sortKey($1)) == .orderedAscending }
        case .artist:
            // Group by artist, then oldest release first so a discography reads chronologically.
            return albums.sorted {
                if let order = Self.compare($0.artist, $1.artist) { return order }
                if $0.year != $1.year { return ($0.year ?? Int.max) < ($1.year ?? Int.max) }
                return nameAscending($0, $1)
            }
        case .mostPlayed:
            return albums.sorted {
                let a = $0.playCount ?? 0, b = $1.playCount ?? 0
                return a != b ? a > b : nameAscending($0, $1)
            }
        case .recentlyPlayed:
            return albums.sorted {
                let a = $0.played ?? .distantPast, b = $1.played ?? .distantPast
                return a != b ? a > b : nameAscending($0, $1)
            }
        case .genre:
            return albums.sorted {
                if let order = Self.compare($0.genre, $1.genre) { return order }
                return nameAscending($0, $1)
            }
        case .starred:
            // Starred albums first, most recently starred at the top.
            return albums.sorted {
                let a = $0.starred ?? .distantPast, b = $1.starred ?? .distantPast
                return a != b ? a > b : nameAscending($0, $1)
            }
        case .rating:
            return albums.sorted {
                let a = $0.userRating ?? 0, b = $1.userRating ?? 0
                return a != b ? a > b : nameAscending($0, $1)
            }
        }
    }

    /// Orders two optional strings, nil and empty last. Returns nil when they compare equal (or both are
    /// missing) so the caller can fall through to its next tie-breaker.
    private static func compare(_ lhs: String?, _ rhs: String?) -> Bool? {
        let l = lhs ?? "", r = rhs ?? ""
        switch (l.isEmpty, r.isEmpty) {
        case (true, true): return nil
        case (true, false): return false
        case (false, true): return true
        case (false, false):
            let order = l.localizedStandardCompare(r)
            return order == .orderedSame ? nil : order == .orderedAscending
        }
    }

    private func nameAscending(_ lhs: AlbumID3, _ rhs: AlbumID3) -> Bool {
        sortKey(lhs).localizedStandardCompare(sortKey(rhs)) == .orderedAscending
    }

    /// Prefer the server's canonical `sortName` (drops articles like "The") when present, else the name.
    private func sortKey(_ album: AlbumID3) -> String { album.sortName ?? album.name }
}

extension AlbumID3 {
    /// The artist name as a non-optional string, for the A–Z jump bar when sorting by artist
    /// (albums with no artist count under "#").
    var artistOrEmpty: String { artist ?? "" }
}
