// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import Foundation

nonisolated enum SidebarSection: String, Hashable, Identifiable, CaseIterable {
    case search
    case home
    case discover
    case radio
    case albums
    case artists
    case playlists
    case favorites
    case downloaded
    case settings

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .search:    return "Search"
        case .home:      return "Home"
        case .discover:  return "Discover"
        case .radio:     return "Radio"
        case .albums:    return "Albums"
        case .artists:   return "Artists"
        case .playlists: return "Playlists"
        case .favorites: return "Favorites"
        case .downloaded: return "Downloaded"
        case .settings:  return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .search:    return "magnifyingglass"
        case .home:      return "house"
        case .discover:  return "sparkles"
        case .radio:     return "antenna.radiowaves.left.and.right"
        case .albums:    return "square.stack"
        case .artists:   return "music.mic"
        case .playlists: return "music.note.list"
        case .favorites: return "heart"
        case .downloaded: return "arrow.down.circle"
        case .settings:  return "gear"
        }
    }
}

nonisolated enum SidebarDestination: Hashable {
    case section(SidebarSection)
    case pinned(String) // PinnedItem.id — "{type}:{itemId}"
}
#endif
