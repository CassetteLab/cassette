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

    /// Shown in the sort menus. `String(localized:)` and not a bare literal: the menus pass this
    /// through as a `String`, which SwiftUI does not localize on its own.
    var label: String {
        switch self {
        case .recentlyAdded: return String(localized: "Recently Added")
        case .releaseYear: return String(localized: "Release Year")
        case .name: return String(localized: "Name")
        case .artist: return String(localized: "Artist")
        case .mostPlayed: return String(localized: "Most Played")
        case .recentlyPlayed: return String(localized: "Recently Played")
        case .genre: return String(localized: "Genre")
        case .starred: return String(localized: "Starred")
        case .rating: return String(localized: "Rating")
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

    private func sortKey(_ album: AlbumID3) -> String { album.alphabetSortKey }
}

// MARK: - A–Z jump bar

nonisolated extension AlbumSort {
    /// What the bar files albums under, or `nil` when this ordering is not alphabetical at all.
    ///
    /// It has to be the same key the list is sorted by, or the bar lies: a name-ordered list uses
    /// the server's `sortName`, so "The Bends" sits under B while keying the bar on `name` would
    /// file it under T and scroll somewhere else entirely.
    var alphabetKeyPath: KeyPath<AlbumID3, String>? {
        switch self {
        case .name:   return \.alphabetSortKey
        case .artist: return \.artistOrEmpty
        default:      return nil
        }
    }

    /// The albums the bar can actually reach.
    ///
    /// Under `.artist`, "#" would otherwise stand for two groups at opposite ends of the list:
    /// artists whose initial is not a letter sort to the top, while albums with no artist sort
    /// last. One letter cannot point at both, so the nameless tail is left out of the bar — it is
    /// still there, at the bottom, a scroll away.
    func alphabetAddressableAlbums(_ albums: [AlbumID3]) -> [AlbumID3] {
        guard self == .artist else { return albums }
        return albums.filter { !$0.artistOrEmpty.isEmpty }
    }
}

nonisolated extension AlbumID3 {
    /// The artist name as a non-optional string, for the A–Z jump bar when sorting by artist.
    var artistOrEmpty: String { artist ?? "" }

    /// What a name-ordered list is really sorted by: the server's canonical `sortName` when it has
    /// one (it drops articles like "The"), else the name.
    var alphabetSortKey: String { sortName ?? name }
}
