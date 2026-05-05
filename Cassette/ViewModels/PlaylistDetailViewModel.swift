// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftUI
import SwiftSonic
import OSLog

@Observable
@MainActor
final class PlaylistDetailViewModel {
    var name: String = ""
    var owner: String? = nil
    var coverArtId: String? = nil
    var songs: [DisplayableSong] = []
    var isOffline: Bool = false
    var isLoading = false
    var error: UserFacingError?
    var isDownloadingPlaylist = false
    var downloadingIds: Set<String> = []

    private(set) var playlistDetail: PlaylistWithSongs?
    private let playlistId: String
    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let playlistService: any PlaylistServiceProtocol
    private let toastService: ToastService
    private let serverState: ServerState

    init(
        playlistId: String,
        libraryService: any LibraryServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        playlistService: any PlaylistServiceProtocol,
        toastService: ToastService,
        serverState: ServerState
    ) {
        self.playlistId = playlistId
        self.libraryService = libraryService
        self.downloadService = downloadService
        self.playlistService = playlistService
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
        isDownloadingPlaylist = await downloadService.isDownloadingPlaylist(playlistId)
    }

    private func loadFromAPI() async {
        do {
            let apiPlaylist = try await libraryService.playlist(id: playlistId)
            playlistDetail = apiPlaylist
            guard let serverId = serverState.activeServer?.id else { return }
            let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
            name = apiPlaylist.name
            owner = apiPlaylist.owner
            coverArtId = apiPlaylist.coverArt
            songs = (apiPlaylist.entry ?? []).map { DisplayableSong(from: $0, isDownloaded: downloadedIds.contains($0.id)) }
            isOffline = false
        } catch {
            self.error = UserFacingError.from(error)
        }
    }

    private func loadFromLocal() async {
        guard let serverId = serverState.activeServer?.id else { return }
        if let data = await downloadService.localPlaylistData(playlistId: playlistId, serverId: serverId) {
            name = data.name
            coverArtId = data.coverArtId
            songs = data.songs
            isOffline = true
        } else {
            isOffline = true
        }
    }

    func downloadPlaylist() async {
        guard let playlist = playlistDetail, let serverId = serverState.activeServer?.id else { return }
        isDownloadingPlaylist = true
        try? await downloadService.download(playlist: playlist, serverId: serverId)
        let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
        songs = songs.map { song in
            DisplayableSong(
                id: song.id, title: song.title, artist: song.artist,
                albumId: song.albumId, albumName: song.albumName,
                artistId: song.artistId, genre: song.genre,
                duration: song.duration, trackNumber: song.trackNumber,
                isDownloaded: downloadedIds.contains(song.id),
                coverArtId: song.coverArtId, audioFormat: song.audioFormat
            )
        }
        isDownloadingPlaylist = false
    }

    func cancelPlaylistDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in songs {
            await downloadService.cancelDownload(songId: song.id, serverId: serverId)
        }
        isDownloadingPlaylist = false
    }

    func downloadSong(id: String) async {
        guard let song = playlistDetail?.entry?.first(where: { $0.id == id }),
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
                coverArtId: s.coverArtId, audioFormat: s.audioFormat
            )
        }
    }

    func downloadMissingTracks() async {
        guard let playlist = playlistDetail,
              let serverId = serverState.activeServer?.id,
              let allSongs = playlist.entry else { return }
        let downloadedIds = Set(songs.filter { $0.isDownloaded }.map(\.id))
        let missing = allSongs.filter { !downloadedIds.contains($0.id) }
        guard !missing.isEmpty else { return }
        isDownloadingPlaylist = true
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
                            coverArtId: $0.coverArtId, audioFormat: $0.audioFormat)
        }
        isDownloadingPlaylist = false
    }

    func deleteDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in songs {
            try? await downloadService.remove(songId: song.id, serverId: serverId)
        }
        try? await downloadService.remove(playlistId: playlistId, serverId: serverId)
        songs = songs.map {
            DisplayableSong(id: $0.id, title: $0.title, artist: $0.artist,
                            albumId: $0.albumId, albumName: $0.albumName,
                            artistId: $0.artistId, genre: $0.genre,
                            duration: $0.duration, trackNumber: $0.trackNumber,
                            isDownloaded: false,
                            coverArtId: $0.coverArtId, audioFormat: $0.audioFormat)
        }
    }

    func removeTrack(at index: Int) async {
        guard songs.indices.contains(index) else { return }
        let removed = songs[index]
        songs.remove(at: index)
        do {
            try await playlistService.removeTracks(playlistId: playlistId, indices: [index])
        } catch {
            songs.insert(removed, at: index)
            Logger.playlist.error("PlaylistDetailViewModel: remove track failed: \(error)")
            toastService.showError("Failed to remove track")
        }
    }

    func moveTracks(from source: IndexSet, to destination: Int) async {
        let originalSongs = songs
        songs.move(fromOffsets: source, toOffset: destination)
        let newOrder = songs.map(\.id)
        do {
            try await playlistService.reorderTracks(playlistId: playlistId, orderedSongIds: newOrder)
        } catch {
            songs = originalSongs
            Logger.playlist.error("PlaylistDetailViewModel: reorder failed: \(error)")
            toastService.showError("Failed to reorder tracks")
        }
    }
}
