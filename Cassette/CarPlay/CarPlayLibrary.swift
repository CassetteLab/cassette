// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import OSLog
import SwiftSonic
import UIKit

/// Cassette's CarPlay library: a tab bar over playlists, recent albums and favourites.
///
/// CarPlay wants its templates synchronously, so each tab is handed over empty and filled by
/// `updateSections` once the server answers. A driver sees the tab bar immediately rather than a
/// frozen screen, and a tab that fails says so instead of staying blank forever.
@MainActor
final class CarPlayLibrary {
    private let container: AppContainer
    private let interfaceController: CPInterfaceController

    private let playlistsTemplate: CPListTemplate
    private let albumsTemplate: CPListTemplate
    private let favoritesTemplate: CPListTemplate

    /// Never hardcoded: CarPlay refuses a list longer than this, and the cap moves between releases.
    private var itemLimit: Int { CPListTemplate.maximumItemCount }

    /// How many covers go in the top row. CarPlay silently drops the extras, and this is the only
    /// number here that is not read from an API — confirm it against CPListImageRowItem's own cap.
    private let imageRowCount = 8

    init(container: AppContainer, interfaceController: CPInterfaceController) {
        self.container = container
        self.interfaceController = interfaceController

        playlistsTemplate = CPListTemplate(title: "Playlists", sections: [])
        playlistsTemplate.tabTitle = "Playlists"
        playlistsTemplate.tabImage = UIImage(systemName: "music.note.list")

        albumsTemplate = CPListTemplate(title: "Albums", sections: [])
        albumsTemplate.tabTitle = "Albums"
        albumsTemplate.tabImage = UIImage(systemName: "square.stack")

        favoritesTemplate = CPListTemplate(title: "Favourites", sections: [])
        favoritesTemplate.tabTitle = "Favourites"
        favoritesTemplate.tabImage = UIImage(systemName: "heart")
    }

    func start() {
        let tabBar = CPTabBarTemplate(templates: [playlistsTemplate, albumsTemplate, favoritesTemplate])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        for template in [playlistsTemplate, albumsTemplate, favoritesTemplate] {
            template.updateSections([CPListSection(items: [CPListItem(text: "Loading…", detailText: nil)])])
        }

        Task { await loadPlaylists() }
        Task { await loadAlbums() }
        Task { await loadFavorites() }
    }

    // MARK: - Loading

    private func loadPlaylists() async {
        do {
            let playlists = try await container.libraryService.playlists()
            let items = playlists.prefix(itemLimit).map { playlist in
                item(
                    title: playlist.name,
                    subtitle: trackCount(playlist.songCount),
                    coverArtId: playlist.coverArt
                ) { [weak self] in
                    await self?.playPlaylist(id: playlist.id)
                }
            }
            fill(playlistsTemplate, with: Array(items), emptyMessage: "No playlists")
        } catch {
            fail(playlistsTemplate, error, what: "playlists")
        }
    }

    private func loadAlbums() async {
        do {
            let albums = Array(try await container.libraryService.recentlyAddedAlbums(size: itemLimit)
                .prefix(itemLimit))
            guard !albums.isEmpty else {
                fill(albumsTemplate, with: [], emptyMessage: "No albums")
                return
            }

            // The list goes up first with no covers at all, then the covers land on it. Waiting for
            // the artwork would leave a driver looking at a spinner over a mobile connection.
            let items = albums.map { album in
                item(title: album.name, subtitle: album.artist, coverArtId: album.coverArt) { [weak self] in
                    await self?.playAlbum(id: album.id)
                }
            }
            albumsTemplate.updateSections([CPListSection(items: items, header: "Recently added", sectionIndexTitle: nil)])

            await addCoverRow(for: Array(albums.prefix(imageRowCount)), below: items)
        } catch {
            fail(albumsTemplate, error, what: "albums")
        }
    }

    /// Adds the Deezer-style row of covers above the list, once its images are in hand.
    private func addCoverRow(for albums: [AlbumID3], below items: [CPListItem]) async {
        let ids = albums.compactMap(\.coverArt)
        guard !ids.isEmpty else { return }
        let images = await CarPlayArtwork.load(
            coverArtIds: ids,
            cache: container.artworkImageCache,
            size: CPListImageRowItem.maximumImageSize
        )
        guard images.count == ids.count else { return }

        let row = CPListImageRowItem(text: "Jump back in", images: images)
        row.listImageRowHandler = { [weak self] _, index, completion in
            Task { @MainActor in
                guard let self, albums.indices.contains(index) else { completion(); return }
                await self.playAlbum(id: albums[index].id)
                completion()
            }
        }
        albumsTemplate.updateSections([
            CPListSection(items: [row]),
            CPListSection(items: items, header: "Recently added", sectionIndexTitle: nil),
        ])
    }

    private func loadFavorites() async {
        do {
            let songs = try await container.libraryService.getStarred2().song ?? []
            let tracks = songs.map { DisplayableSong(from: $0) }
            let items = tracks.prefix(itemLimit).enumerated().map { index, track in
                item(title: track.title, subtitle: track.artist, coverArtId: track.coverArtId) { [weak self] in
                    // Starts the whole favourites list at the tapped track, so the queue carries on
                    // afterwards instead of stopping at one song.
                    await self?.play(Array(tracks.prefix(self?.itemLimit ?? 0)), startIndex: index)
                }
            }
            fill(favoritesTemplate, with: Array(items), emptyMessage: "No favourites")
        } catch {
            fail(favoritesTemplate, error, what: "favourites")
        }
    }

    // MARK: - Playback

    private func playPlaylist(id: String) async {
        do {
            let tracks = (try await container.libraryService.playlist(id: id).entry ?? [])
                .map { DisplayableSong(from: $0) }
            await play(tracks, startIndex: 0)
        } catch {
            log(error, what: "playlist")
        }
    }

    private func playAlbum(id: String) async {
        do {
            let tracks = (try await container.libraryService.album(id: id).song ?? [])
                .map { DisplayableSong(from: $0) }
            await play(tracks, startIndex: 0)
        } catch {
            log(error, what: "album")
        }
    }

    private func play(_ tracks: [DisplayableSong], startIndex: Int) async {
        guard !tracks.isEmpty else { return }
        do {
            try await container.playerService.play(tracks: tracks, startIndex: startIndex)
            showNowPlaying()
        } catch {
            log(error, what: "playback")
        }
    }

    private func showNowPlaying() {
        // Pushing again when it is already on top would stack a second copy, and the driver would
        // need two taps to get back to the list.
        guard interfaceController.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    // MARK: - Helpers

    private func item(
        title: String,
        subtitle: String?,
        coverArtId: String? = nil,
        action: @escaping @MainActor () async -> Void
    ) -> CPListItem {
        let listItem = CPListItem(text: title, detailText: subtitle)
        listItem.handler = { _, completion in
            Task { @MainActor in
                await action()
                completion()
            }
        }
        CarPlayArtwork.attach(
            to: listItem,
            coverArtId: coverArtId,
            cache: container.artworkImageCache,
            size: CPListItem.maximumImageSize
        )
        return listItem
    }

    private func fill(_ template: CPListTemplate, with items: [CPListItem], emptyMessage: String) {
        guard !items.isEmpty else {
            template.updateSections([CPListSection(items: [CPListItem(text: emptyMessage, detailText: nil)])])
            return
        }
        template.updateSections([CPListSection(items: items)])
    }

    private func fail(_ template: CPListTemplate, _ error: Error, what: String) {
        log(error, what: what)
        template.updateSections([CPListSection(items: [CPListItem(text: "Unavailable", detailText: nil)])])
    }

    /// Logs the error type only. A description could carry the server URL or a credential, and
    /// nothing in Cassette puts those in a log.
    private func log(_ error: Error, what: String) {
        Logger.carPlay.error("Failed to load \(what, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
    }

    private func trackCount(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 1 ? "1 track" : "\(count) tracks"
    }
}
#endif
