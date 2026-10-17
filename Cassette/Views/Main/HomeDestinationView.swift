// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

#if os(iOS)
/// Shares destination construction between Home and the iPad library tabs.
struct HomeDestinationView: View {
    let destination: HomeDestination
    var pinnedZoomNamespace: Namespace.ID? = nil
    var recentlyAddedZoomNamespace: Namespace.ID? = nil
    var playlistZoomNamespace: Namespace.ID? = nil
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkImageCache

    var body: some View {
        switch destination {
        case .libraryAlbums:
            AlbumsListView()
        case .libraryArtists:
            ArtistListView()
        case .librarySongs:
            SongsListView()
        case .libraryPlaylists:
            PlaylistListView(zoomNamespace: playlistZoomNamespace)
        case .libraryFavorites:
            FavoritesView()
        case .libraryDownloads:
            DownloadedView()
        case .album(let album):
            AlbumDetailView(
                album: album,
                zoomSourceId: album.id,
                zoomNamespace: recentlyAddedZoomNamespace,
                coverArtId: album.coverArt,
                initialDominantColor: colorExtractor.dominantColor(for: album.coverArt ?? album.id, image: nil),
                initialCoverImage: artworkImageCache.cachedImage(for: album.coverArt ?? album.id)
            )
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .playlist(let playlist):
            PlaylistDetailView(
                playlist: playlist,
                coverArtId: playlist.coverArt ?? playlist.id,
                initialCoverImage: artworkImageCache.cachedImage(for: playlist.coverArt ?? playlist.id),
                zoomSourceId: playlist.id,
                zoomNamespace: playlistZoomNamespace
            )
        case .downloadedAlbum(let display):
            AlbumDetailView(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId, mode: .downloadedOnly)
        case .albumById(let id, let name, _, let coverArtId, let hasZoomSource):
            AlbumDetailView(
                albumId: id,
                albumName: name,
                zoomSourceId: hasZoomSource ? id : nil,
                zoomNamespace: hasZoomSource ? pinnedZoomNamespace : nil,
                coverArtId: coverArtId,
                initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id)
            )
        case .playlistById(let id, let name, let coverArtId, let hasZoomSource):
            PlaylistDetailView(
                playlistId: id,
                name: name,
                coverArtId: coverArtId,
                initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id),
                zoomSourceId: hasZoomSource ? id : nil,
                zoomNamespace: hasZoomSource ? pinnedZoomNamespace : nil
            )
        case .artistById(let id, let name, let coverArtId):
            ArtistDetailView(artist: ArtistID3(id: id, name: name, coverArt: coverArtId))
        case .artistBestOf(let id, let name, let coverArtId):
            ArtistBestOfView(artistId: id, artistName: name, coverArtId: coverArtId)
        case .offlineArtist(let artist):
            OfflineArtistAlbumsView(artist: artist)
        case .offlineAlbum(let album):
            AlbumDetailView(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
        }
    }
}
#endif
