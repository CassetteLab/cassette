// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import Foundation

nonisolated enum SidebarSection: String, Hashable, Identifiable, CaseIterable {
    case home
    case radio
    case freshReleases
    case wrapped
    case albums
    case artists
    case songs
    case playlists
    case favorites
    case downloads

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .home:      return "Home"
        case .radio:         return "Radio"
        case .freshReleases: return "Fresh Releases"
        case .wrapped:       return "Wrapped"
        case .albums:        return "Albums"
        case .artists:   return "Artists"
        case .songs:     return "Songs"
        case .playlists: return "Playlists"
        case .favorites: return "Favorites"
        case .downloads: return "Downloads"
        }
    }

    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .radio:         return "antenna.radiowaves.left.and.right"
        case .freshReleases: return "sparkles"
        case .wrapped:       return "play.square.stack"
        case .albums:        return "square.stack"
        case .artists:   return "music.mic"
        case .songs:     return "music.note"
        case .playlists: return "music.note.list"
        case .favorites: return "star"
        case .downloads: return "arrow.down.circle"
        }
    }
}

nonisolated enum SidebarDestination: Hashable {
    case section(SidebarSection)
    case pinned(String) // PinnedItem.id — "{type}:{itemId}"
}
#endif
