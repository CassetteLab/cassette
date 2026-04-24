// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class AlbumDetailViewModel {
    var album: AlbumID3?
    var isLoading = false
    var error: Error?
    var downloadedSongIds: Set<String> = []
    var isDownloadingAlbum = false

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
        do {
            album = try await libraryService.album(id: albumId)
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

    func downloadAlbum() async {
        guard let album, let serverId = serverState.activeServer?.id else { return }
        isDownloadingAlbum = true
        try? await downloadService.download(album: album, serverId: serverId)
        await loadDownloadState()
        isDownloadingAlbum = false
    }

    func cancelAlbumDownload() async {
        guard let serverId = serverState.activeServer?.id else { return }
        for song in album?.song ?? [] {
            await downloadService.cancelDownload(songId: song.id, serverId: serverId)
        }
        isDownloadingAlbum = false
    }
}
