// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import OSLog
import SwiftSonic
import UIKit

/// Cassette's CarPlay interface: Home, Recents, Library and Search.
///
/// CarPlay wants its templates synchronously, so every tab is handed over empty and filled by
/// `updateSections` once the server answers. A driver sees the tab bar immediately rather than a
/// frozen screen, and a tab that fails says so instead of staying blank.
@MainActor
final class CarPlayLibrary {
    let container: AppContainer
    let interfaceController: CPInterfaceController

    private let homeTemplate: CPListTemplate
    private let recentsTemplate: CPListTemplate
    private let libraryTemplate: CPListTemplate
    private let searchTemplate = CPSearchTemplate()
    private var search: CarPlaySearch?
    private var nowPlaying: CarPlayNowPlaying?

    /// Never hardcoded: CarPlay refuses a list longer than this, and the cap moves between releases.
    var itemLimit: Int { CPListTemplate.maximumItemCount }

    /// How many covers go in a top row. CarPlay drops the extras silently, and this is the only
    /// number here that is not read from an API — confirm it against CPListImageRowItem's own cap.
    private let imageRowCount = 8

    init(container: AppContainer, interfaceController: CPInterfaceController) {
        self.container = container
        self.interfaceController = interfaceController

        homeTemplate = CPListTemplate(title: "Home", sections: [])
        homeTemplate.tabTitle = "Home"
        homeTemplate.tabImage = UIImage(systemName: "house")

        recentsTemplate = CPListTemplate(title: "Recents", sections: [])
        recentsTemplate.tabTitle = "Recents"
        recentsTemplate.tabImage = UIImage(systemName: "clock")

        libraryTemplate = CPListTemplate(title: "Library", sections: [])
        libraryTemplate.tabTitle = "Library"
        libraryTemplate.tabImage = UIImage(systemName: "music.note.house")

        searchTemplate.tabTitle = "Search"
        searchTemplate.tabImage = UIImage(systemName: "magnifyingglass")
    }

    func start() {
        let search = CarPlaySearch(library: self)
        self.search = search
        searchTemplate.delegate = search

        let nowPlaying = CarPlayNowPlaying(library: self)
        self.nowPlaying = nowPlaying
        nowPlaying.configure()

        let tabBar = CPTabBarTemplate(templates: [homeTemplate, recentsTemplate, libraryTemplate, searchTemplate])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        buildLibraryMenu()
        for template in [homeTemplate, recentsTemplate] {
            template.updateSections([CPListSection(items: [CPListItem(text: "Loading…", detailText: nil)])])
        }

        Task { await loadHome() }
        Task { await loadRecents() }
    }

    // MARK: - Home

    private func loadHome() async {
        do {
            let recent = Array(try await container.libraryService.recentlyAddedAlbums(size: itemLimit)
                .prefix(itemLimit))
            guard !recent.isEmpty else {
                fill(homeTemplate, with: [], emptyMessage: "Nothing here yet")
                return
            }

            // The list goes up with no covers at all, then the covers land on it. Waiting for the
            // artwork would leave a driver looking at a spinner over a mobile connection.
            let items = recent.map(albumItem)
            homeTemplate.updateSections([section(items, header: "Recently added")])

            let heads = Array(recent.prefix(imageRowCount))
            if let row = await coverRow(for: heads, title: "Jump back in") {
                homeTemplate.updateSections([CPListSection(items: [row]), section(items, header: "Recently added")])
            }
        } catch {
            fail(homeTemplate, error, what: "home")
        }
    }

    private func loadRecents() async {
        do {
            let albums = Array(try await container.libraryService.recentlyPlayedAlbums(size: itemLimit)
                .prefix(itemLimit))
            fill(recentsTemplate, with: albums.map(albumItem), emptyMessage: "Nothing played yet")
        } catch {
            fail(recentsTemplate, error, what: "recents")
        }
    }

    // MARK: - Library

    private func buildLibraryMenu() {
        let entries: [(String, String, @MainActor () async -> Void)] = [
            ("Playlists", "music.note.list", { [weak self] in await self?.showPlaylists() }),
            ("Albums", "square.stack", { [weak self] in await self?.showAlbums() }),
            ("Artists", "person", { [weak self] in await self?.showArtists() }),
            ("Favourites", "heart", { [weak self] in await self?.showFavourites() }),
        ]
        let items = entries.map { title, symbol, action -> CPListItem in
            let item = CPListItem(text: title, detailText: nil)
            item.setImage(UIImage(systemName: symbol))
            item.handler = { _, completion in
                Task { @MainActor in
                    await action()
                    completion()
                }
            }
            return item
        }
        libraryTemplate.updateSections([CPListSection(items: items)])
    }

    private func showPlaylists() async {
        await push(title: "Playlists", loading: {
            let playlists = try await self.container.libraryService.playlists()
            return playlists.prefix(self.itemLimit).map { playlist in
                self.item(title: playlist.name, subtitle: self.trackCount(playlist.songCount), coverArtId: playlist.coverArt) { [weak self] in
                    await self?.openPlaylist(playlist)
                }
            }
        })
    }

    private func showAlbums() async {
        await push(title: "Albums", loading: {
            let albums = try await self.container.libraryService.allAlbums()
            return albums.prefix(self.itemLimit).map(self.albumItem)
        })
    }

    private func showArtists() async {
        await push(title: "Artists", loading: {
            let artists = try await self.container.libraryService.artists().flatMap(\.artist)
            return artists.prefix(self.itemLimit).map { artist in
                self.item(title: artist.name, subtitle: nil, coverArtId: artist.coverArt) { [weak self] in
                    await self?.openArtist(artist)
                }
            }
        })
    }

    private func showFavourites() async {
        await push(title: "Favourites", loading: {
            let tracks = (try await self.container.libraryService.getStarred2().song ?? [])
                .map { DisplayableSong(from: $0) }
            return self.songItems(Array(tracks.prefix(self.itemLimit)))
        })
    }

    // MARK: - Detail screens

    private func openPlaylist(_ playlist: Playlist) async {
        await push(title: playlist.name, loading: {
            let tracks = (try await self.container.libraryService.playlist(id: playlist.id).entry ?? [])
                .map { DisplayableSong(from: $0) }
            return self.playAllHeader(tracks) + self.songItems(Array(tracks.prefix(self.itemLimit)))
        })
    }

    func openAlbum(_ album: AlbumID3) async {
        await push(title: album.name, loading: {
            let tracks = (try await self.container.libraryService.album(id: album.id).song ?? [])
                .map { DisplayableSong(from: $0) }
            return self.playAllHeader(tracks) + self.songItems(Array(tracks.prefix(self.itemLimit)))
        })
    }

    func openArtist(_ artist: ArtistID3) async {
        await push(title: artist.name, loading: {
            let albums = try await self.container.libraryService.artist(id: artist.id).album ?? []
            return albums.prefix(self.itemLimit).map(self.albumItem)
        })
    }

    /// A driver should not have to pick a first track to start a record. This is always the top row.
    private func playAllHeader(_ tracks: [DisplayableSong]) -> [CPListItem] {
        guard !tracks.isEmpty else { return [] }
        let item = CPListItem(text: "Play all", detailText: trackCount(tracks.count))
        item.setImage(UIImage(systemName: "play.fill"))
        item.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.play(tracks, startIndex: 0)
                completion()
            }
        }
        return [item]
    }

    // MARK: - Playback

    func play(_ tracks: [DisplayableSong], startIndex: Int) async {
        guard !tracks.isEmpty else { return }
        do {
            try await container.playerService.play(tracks: tracks, startIndex: startIndex)
            nowPlaying?.refreshButtons()
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

    // MARK: - Building blocks

    func albumItem(_ album: AlbumID3) -> CPListItem {
        item(title: album.name, subtitle: album.artist, coverArtId: album.coverArt) { [weak self] in
            await self?.openAlbum(album)
        }
    }

    /// Every track starts the whole list at its own index, so the queue carries on afterwards
    /// instead of stopping after one song.
    func songItems(_ tracks: [DisplayableSong]) -> [CPListItem] {
        tracks.enumerated().map { index, track in
            item(title: track.title, subtitle: track.artist, coverArtId: track.coverArtId) { [weak self] in
                await self?.play(tracks, startIndex: index)
            }
        }
    }

    func item(
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

    private func coverRow(for albums: [AlbumID3], title: String) async -> CPListImageRowItem? {
        let ids = albums.compactMap(\.coverArt)
        guard !ids.isEmpty else { return nil }
        let images = await CarPlayArtwork.load(
            coverArtIds: ids,
            cache: container.artworkImageCache,
            size: CPListImageRowItem.maximumImageSize
        )
        // A partial fetch would misalign images and albums, and the driver would tap the wrong record.
        guard images.count == ids.count else { return nil }

        let row = CPListImageRowItem(text: title, images: images)
        row.listImageRowHandler = { [weak self] _, index, completion in
            Task { @MainActor in
                guard let self, albums.indices.contains(index) else { completion(); return }
                await self.openAlbum(albums[index])
                completion()
            }
        }
        return row
    }

    /// Pushes a screen that is already on display while its contents load, so a tap never looks lost.
    private func push(title: String, loading: @escaping @MainActor () async throws -> [CPListItem]) async {
        let template = CPListTemplate(title: title, sections: [
            CPListSection(items: [CPListItem(text: "Loading…", detailText: nil)]),
        ])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
        do {
            let items = try await loading()
            fill(template, with: items, emptyMessage: "Nothing here")
        } catch {
            fail(template, error, what: title)
        }
    }

    // MARK: - Helpers

    private func section(_ items: [CPListItem], header: String) -> CPListSection {
        CPListSection(items: items, header: header, sectionIndexTitle: nil)
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
    func log(_ error: Error, what: String) {
        Logger.carPlay.error("Failed to load \(what, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
    }

    func trackCount(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 1 ? "1 track" : "\(count) tracks"
    }
}
#endif
