// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class PlaylistDetailViewModel {
    var playlist: PlaylistWithSongs?
    var isLoading = false
    var error: Error?
    var downloadedSongIds: Set<String> = []
    var isDownloadingPlaylist = false

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
        do {
            playlist = try await libraryService.playlist(id: playlistId)
            await loadDownloadState()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadDownloadState() async {
        guard let serverId = serverState.activeServer?.id else { return }
        downloadedSongIds = await downloadService.downloadedSongIds(serverId: serverId)
    }

    func downloadPlaylist() async {
        guard let playlist, let serverId = serverState.activeServer?.id else { return }
        isDownloadingPlaylist = true
        try? await downloadService.download(playlist: playlist, serverId: serverId)
        await loadDownloadState()
        isDownloadingPlaylist = false
    }

    func cancelPlaylistDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in playlist?.entry ?? [] {
            await downloadService.cancelDownload(songId: song.id, serverId: serverId)
        }
        isDownloadingPlaylist = false
    }
}
