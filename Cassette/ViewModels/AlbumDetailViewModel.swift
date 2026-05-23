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
            await loadFromLocal()
        }
        isLoading = false
        isDownloadingAlbum = await downloadService.isDownloadingAlbum(albumId)
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
            artistId = apiAlbum.artistId
            songs = (apiAlbum.song ?? []).map { DisplayableSong(from: $0, isDownloaded: downloadedIds.contains($0.id)) }
            isOffline = false
        } catch {
            self.error = UserFacingError.from(error)
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
                albumId: song.albumId, albumName: song.albumName,
                artistId: song.artistId, genre: song.genre,
                duration: song.duration, trackNumber: song.trackNumber,
                isDownloaded: downloadedIds.contains(song.id),
                coverArtId: song.coverArtId, audioFormat: song.audioFormat,
                replayGainTrackGain: song.replayGainTrackGain,
                replayGainTrackPeak: song.replayGainTrackPeak,
                replayGainAlbumGain: song.replayGainAlbumGain,
                replayGainAlbumPeak: song.replayGainAlbumPeak
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

    func downloadSong(id: String) async {
        guard let song = loadedAlbum?.song?.first(where: { $0.id == id }),
              let serverId = serverState.activeServer?.id else { return }
        downloadingIds.insert(id)
        defer { downloadingIds.remove(id) }
        try? await downloadService.download(song: song, serverId: serverId)
        let allDownloaded = await downloadService.downloadedSongIds(serverId: serverId)
        if let idx = songs.firstIndex(where: { $0.id == id }) {
            let s = songs[idx]
            songs[idx] = DisplayableSong(
                id: s.id, title: s.title, artist: s.artist,
                albumId: s.albumId, albumName: s.albumName,
                artistId: s.artistId, genre: s.genre,
                duration: s.duration, trackNumber: s.trackNumber,
                isDownloaded: allDownloaded.contains(id),
                coverArtId: s.coverArtId, audioFormat: s.audioFormat,
                replayGainTrackGain: s.replayGainTrackGain,
                replayGainTrackPeak: s.replayGainTrackPeak,
                replayGainAlbumGain: s.replayGainAlbumGain,
                replayGainAlbumPeak: s.replayGainAlbumPeak
            )
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
        songs = songs.map {
            DisplayableSong(id: $0.id, title: $0.title, artist: $0.artist,
                            albumId: $0.albumId, albumName: $0.albumName,
                            artistId: $0.artistId, genre: $0.genre,
                            duration: $0.duration, trackNumber: $0.trackNumber,
                            isDownloaded: allDownloaded.contains($0.id),
                            coverArtId: $0.coverArtId, audioFormat: $0.audioFormat,
                            replayGainTrackGain: $0.replayGainTrackGain,
                            replayGainTrackPeak: $0.replayGainTrackPeak,
                            replayGainAlbumGain: $0.replayGainAlbumGain,
                            replayGainAlbumPeak: $0.replayGainAlbumPeak)
        }
        isDownloadingAlbum = false
    }

    func deleteDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        try? await downloadService.remove(albumId: albumId, serverId: serverId)
        songs = songs.map {
            DisplayableSong(id: $0.id, title: $0.title, artist: $0.artist,
                            albumId: $0.albumId, albumName: $0.albumName,
                            artistId: $0.artistId, genre: $0.genre,
                            duration: $0.duration, trackNumber: $0.trackNumber,
                            isDownloaded: false,
                            coverArtId: $0.coverArtId, audioFormat: $0.audioFormat,
                            replayGainTrackGain: $0.replayGainTrackGain,
                            replayGainTrackPeak: $0.replayGainTrackPeak,
                            replayGainAlbumGain: $0.replayGainAlbumGain,
                            replayGainAlbumPeak: $0.replayGainAlbumPeak)
        }
    }
}
