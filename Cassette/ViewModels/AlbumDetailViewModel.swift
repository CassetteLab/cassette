// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class AlbumDetailViewModel {
    var albumName: String = ""
    var artistName: String? = nil
    var year: Int? = nil
    var genre: String? = nil
    var songCount: Int = 0
    var coverArtId: String? = nil
    var artistId: String? = nil
    var songs: [DisplayableSong] = []
    var isOffline: Bool = false
    var isLoading = false
    var error: UserFacingError?
    var isDownloadingAlbum = false
    var downloadingIds: Set<String> = []

    private var loadedAlbum: AlbumID3?
    private let albumId: String
    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let toastService: ToastService
    private let serverState: ServerState

    init(
        albumId: String,
        libraryService: any LibraryServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        toastService: ToastService,
        serverState: ServerState
    ) {
        self.albumId = albumId
        self.libraryService = libraryService
        self.downloadService = downloadService
        self.toastService = toastService
        self.serverState = serverState
    }

    func load() async {
        isLoading = true
        error = nil
        if serverState.isOnline {
            await loadFromAPI()
        } else {
            isOffline = true
            await loadFromLocal()
        }
        isLoading = false
        isDownloadingAlbum = await downloadService.isDownloadingAlbum(albumId)
    }

    private func loadFromAPI() async {
        do {
            let apiAlbum = try await libraryService.album(id: albumId)
            // Empty-success guard: behind a captive proxy / Cloudflare-WARP edge the server
            // is reachable but answers 200 with no songs. That never throws, so the catch
            // below can't help — treat an empty result exactly like a failure and prefer the
            // downloaded copy before clobbering the UI with an empty state.
            if (apiAlbum.song ?? []).isEmpty, await loadFromLocal() { return }
            loadedAlbum = apiAlbum
            guard let serverId = serverState.activeServer?.id else { return }
            let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
            albumName = apiAlbum.name
            artistName = apiAlbum.artist
            year = apiAlbum.year
            genre = apiAlbum.genre
            songCount = apiAlbum.songCount
            coverArtId = apiAlbum.coverArt
            artistId = apiAlbum.artistId
            songs = (apiAlbum.song ?? []).map { DisplayableSong(from: $0, isDownloaded: downloadedIds.contains($0.id)) }
            isOffline = false
        } catch {
            // Server unreachable (airplane mode with stale isOnline, VPN-satisfied path,
            // server down): fall back to the downloaded copy before surfacing an error.
            if await loadFromLocal() { return }
            self.error = UserFacingError.from(error)
        }
    }

    /// Returns true when a downloaded copy with at least one track was loaded.
    /// Sets isOffline only on success — a transient online failure must not flip
    /// the UI into offline mode while songs from a previous load are still shown.
    @discardableResult
    private func loadFromLocal() async -> Bool {
        guard let serverId = serverState.activeServer?.id,
              let data = await downloadService.localAlbumData(albumId: albumId, serverId: serverId),
              !data.songs.isEmpty else { return false }
        albumName = data.albumName
        artistName = data.artistName
        coverArtId = data.coverArtId
        songCount = data.songs.count
        songs = data.songs
        // Offline records carry no year/genre/artistId — clear stale online values so a re-load after going
        // offline (the long-lived VM re-runs load() on connectivity change) doesn't keep showing them.
        year = nil
        genre = nil
        artistId = nil
        isOffline = true
        return true
    }

    func downloadAlbum() async {
        guard let album = loadedAlbum, let serverId = serverState.activeServer?.id else { return }
        isDownloadingAlbum = true
        try? await downloadService.download(album: album, serverId: serverId)
        let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
        songs = songs.map { $0.withDownloaded(downloadedIds.contains($0.id)) }
        isDownloadingAlbum = false
    }

    func cancelAlbumDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in songs {
            await downloadService.cancelDownload(songId: song.id, serverId: serverId)
        }
        isDownloadingAlbum = false
    }

    func downloadSong(id: String) async {
        guard let song = loadedAlbum?.song?.first(where: { $0.id == id }),
              let serverId = serverState.activeServer?.id else { return }
        downloadingIds.insert(id)
        defer { downloadingIds.remove(id) }
        try? await downloadService.download(song: song, serverId: serverId)
        let allDownloaded = await downloadService.downloadedSongIds(serverId: serverId)
        if let idx = songs.firstIndex(where: { $0.id == id }) {
            songs[idx] = songs[idx].withDownloaded(allDownloaded.contains(id))
        }
    }

    func downloadMissingTracks() async {
        guard let album = loadedAlbum,
              let serverId = serverState.activeServer?.id,
              let allSongs = album.song else { return }
        let downloadedIds = Set(songs.filter { $0.isDownloaded }.map(\.id))
        let missing = allSongs.filter { !downloadedIds.contains($0.id) }
        guard !missing.isEmpty else { return }
        isDownloadingAlbum = true
        for song in missing {
            try? await downloadService.download(song: song, serverId: serverId)
        }
        let allDownloaded = await downloadService.downloadedSongIds(serverId: serverId)
        songs = songs.map { $0.withDownloaded(allDownloaded.contains($0.id)) }
        isDownloadingAlbum = false
    }

    func deleteDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        try? await downloadService.remove(albumId: albumId, serverId: serverId)
        songs = songs.map { $0.withDownloaded(false) }
    }
}
