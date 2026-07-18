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

    var label: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .releaseYear: return "Release Year"
        case .name: return "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyAdded: return "clock"
        case .releaseYear: return "calendar"
        case .name: return "textformat"
        }
    }

    /// Orders an already-fetched album array. Missing fields (no `created`, no `year`) sort last.
    func sorted(_ albums: [AlbumID3]) -> [AlbumID3] {
        switch self {
        case .recentlyAdded:
            return albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .releaseYear:
            return albums.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
        case .name:
            return albums.sorted { sortKey($0).localizedStandardCompare(sortKey($1)) == .orderedAscending }
        }
    }

    /// Prefer the server's canonical `sortName` (drops articles like "The") when present, else the name.
    private func sortKey(_ album: AlbumID3) -> String { album.sortName ?? album.name }
}
