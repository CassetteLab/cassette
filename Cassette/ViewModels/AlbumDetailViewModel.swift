// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
    var songs: [DisplayableSong] = []
    var isOffline: Bool = false
    var isLoading = false
    var error: Error?
    var isDownloadingAlbum = false

    private var loadedAlbum: AlbumID3?
    private let albumId: String
    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let serverState: ServerState

    init(
        albumId: String,
        libraryService: any LibraryServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        serverState: ServerState
    ) {
        self.albumId = albumId
        self.libraryService = libraryService
        self.downloadService = downloadService
        self.serverState = serverState
    }

    func load() async {
        isLoading = true
        error = nil
        if serverState.isOnline {
            await loadFromAPI()
        } else {
            await loadFromLocal()
        }
        isLoading = false
    }

    private func loadFromAPI() async {
        do {
            let apiAlbum = try await libraryService.album(id: albumId)
            loadedAlbum = apiAlbum
            guard let serverId = serverState.activeServer?.id else { return }
            let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
            albumName = apiAlbum.name
            artistName = apiAlbum.artist
            year = apiAlbum.year
            genre = apiAlbum.genre
            songCount = apiAlbum.songCount
            coverArtId = apiAlbum.coverArt
            songs = (apiAlbum.song ?? []).map { DisplayableSong(from: $0, isDownloaded: downloadedIds.contains($0.id)) }
            isOffline = false
        } catch {
            self.error = error
        }
    }

    private func loadFromLocal() async {
        guard let serverId = serverState.activeServer?.id else { return }
        if let data = await downloadService.localAlbumData(albumId: albumId, serverId: serverId) {
            albumName = data.albumName
            artistName = data.artistName
            coverArtId = data.coverArtId
            songCount = data.songs.count
            songs = data.songs
            isOffline = true
        } else {
            isOffline = true
        }
    }

    func downloadAlbum() async {
        guard let album = loadedAlbum, let serverId = serverState.activeServer?.id else { return }
        isDownloadingAlbum = true
        try? await downloadService.download(album: album, serverId: serverId)
        let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
        songs = songs.map { song in
            DisplayableSong(
                id: song.id, title: song.title, artist: song.artist,
                albumName: song.albumName, duration: song.duration,
                trackNumber: song.trackNumber,
                isDownloaded: downloadedIds.contains(song.id),
                coverArtId: song.coverArtId
            )
        }
        isDownloadingAlbum = false
    }

    func cancelAlbumDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in songs {
            await downloadService.cancelDownload(songId: song.id, serverId: serverId)
        }
        isDownloadingAlbum = false
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
        songs = songs.map {
            DisplayableSong(id: $0.id, title: $0.title, artist: $0.artist,
                            albumName: $0.albumName, duration: $0.duration,
                            trackNumber: $0.trackNumber,
                            isDownloaded: allDownloaded.contains($0.id),
                            coverArtId: $0.coverArtId)
        }
        isDownloadingAlbum = false
    }

    func deleteDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        try? await downloadService.remove(albumId: albumId, serverId: serverId)
        songs = songs.map {
            DisplayableSong(id: $0.id, title: $0.title, artist: $0.artist,
                            albumName: $0.albumName, duration: $0.duration,
                            trackNumber: $0.trackNumber, isDownloaded: false,
                            coverArtId: $0.coverArtId)
        }
    }
}
