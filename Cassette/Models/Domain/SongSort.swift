// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// User-selectable ordering for the "All Songs" library list. String-backed so it persists via
/// `@AppStorage("cassette.songSort")`. Sorts the raw `Song` DTOs (which carry `created`/`year`) before they
/// are mapped to `DisplayableSong` for display.
nonisolated enum SongSort: String, CaseIterable, Sendable {
    case title
    case artist
    case recentlyAdded
    case releaseDate

    var label: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .recentlyAdded: return "Recently Added"
        case .releaseDate: return "Release Date"
        }
    }

    var systemImage: String {
        switch self {
        case .title: return "textformat"
        case .artist: return "music.mic"
        case .recentlyAdded: return "clock"
        case .releaseDate: return "calendar"
        }
    }

    /// Orders songs. Missing fields (no `created`, no `year`) sort last.
    func sorted(_ songs: [Song]) -> [Song] {
        switch self {
        case .title:
            return songs.sorted { key($0).localizedStandardCompare(key($1)) == .orderedAscending }
        case .artist:
            return songs.sorted {
                let byArtist = ($0.artist ?? "").localizedStandardCompare($1.artist ?? "")
                if byArtist != .orderedSame { return byArtist == .orderedAscending }
                return key($0).localizedStandardCompare(key($1)) == .orderedAscending
            }
        case .recentlyAdded:
            return songs.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .releaseDate:
            return songs.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
        }
    }

    /// Prefer the server's canonical `sortName` (drops articles like "The") when present, else the title.
    private func key(_ song: Song) -> String { song.sortName ?? song.title }
}
