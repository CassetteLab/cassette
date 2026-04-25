// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class PlaylistDetailViewModel {
    var name: String = ""
    var owner: String? = nil
    var coverArtId: String? = nil
    var songs: [DisplayableSong] = []
    var isOffline: Bool = false
    var isLoading = false
    var error: Error?
    var isDownloadingPlaylist = false

    private var loadedPlaylist: PlaylistWithSongs?
    private let playlistId: String
    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let serverState: ServerState

    init(
        playlistId: String,
        libraryService: any LibraryServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        serverState: ServerState
    ) {
        self.playlistId = playlistId
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
            let apiPlaylist = try await libraryService.playlist(id: playlistId)
            loadedPlaylist = apiPlaylist
            guard let serverId = serverState.activeServer?.id else { return }
            let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
            name = apiPlaylist.name
            owner = apiPlaylist.owner
            coverArtId = apiPlaylist.coverArt
            songs = (apiPlaylist.entry ?? []).map { DisplayableSong(from: $0, isDownloaded: downloadedIds.contains($0.id)) }
            isOffline = false
        } catch {
            self.error = error
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
        guard let playlist = loadedPlaylist, let serverId = serverState.activeServer?.id else { return }
        isDownloadingPlaylist = true
        try? await downloadService.download(playlist: playlist, serverId: serverId)
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
        isDownloadingPlaylist = false
    }

    func cancelPlaylistDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in songs {
            await downloadService.cancelDownload(songId: song.id, serverId: serverId)
        }
        isDownloadingPlaylist = false
    }
}
