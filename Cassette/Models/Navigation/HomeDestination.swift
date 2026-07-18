// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftSonic

/// All value-based navigation destinations reachable from the Home tab NavigationStack.
/// Registered via .navigationDestination(for: HomeDestination.self) on HomeView.
nonisolated enum HomeDestination: Hashable {

    // MARK: - Library sections (iOS only — macOS uses NavigationSplitView sidebar)
    case libraryAlbums
    case libraryArtists
    case librarySongs
    case libraryPlaylists
    case libraryFavorites
    case libraryDownloads

    // MARK: - Content destinations (iOS + macOS)
    /// Full AlbumID3 object — used from Recently Added, Recently Played carousels
    case album(AlbumID3)
    /// Full ArtistID3 object
    case artist(ArtistID3)
    /// Full Playlist object
    case playlist(Playlist)
    /// Full DownloadedAlbumDisplay object — used from downloaded content carousels
    case downloadedAlbum(DownloadedAlbumDisplay)

    // MARK: - ID-only destinations (for PinnedItem @Model and DownloadedItem)
    /// Used when only IDs are available (PinnedItem @Model, HomeDownloadedItemCard)
    case albumById(id: String, name: String, subtitle: String, coverArtId: String?)
    case playlistById(id: String, name: String, coverArtId: String?)
    case artistById(id: String, name: String, coverArtId: String?)

    // MARK: - Derived (virtual) destinations
    /// "The best of <artist>" — the user's starred tracks for one artist, computed from getStarred2.
    /// Carries only identity: the track list is never persisted, it is recomputed by the screen.
    case artistBestOf(artistId: String, artistName: String, coverArtId: String?)

    // MARK: - Offline-derived destinations
    /// Offline artist summary — used from OfflineBrowseContent
    case offlineArtist(OfflineArtistSummary)
    /// Offline album summary — used from OfflineArtistAlbumsView
    case offlineAlbum(OfflineAlbumSummary)
}
