// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

nonisolated struct DownloadedPlaylistDTO: Identifiable, Sendable {
    let id: UUID
    let playlistId: String
    let serverId: UUID
    let name: String
    let tracksCount: Int
    let totalTracksCount: Int
    var isComplete: Bool { tracksCount == totalTracksCount }
}

@Observable
@MainActor
final class DownloadsViewModel {
    var displayAlbums: [DownloadedAlbumDisplay] = []
    var downloadedPlaylists: [DownloadedPlaylistDTO] = []
    var usedBytesFormatted: String = "—"
    var isClearingAll = false

    private let modelContainer: ModelContainer
    private let downloadService: any DownloadServiceProtocol
    private let serverState: ServerState

    init(
        modelContainer: ModelContainer,
        downloadService: any DownloadServiceProtocol,
        serverState: ServerState
    ) {
        self.modelContainer = modelContainer
        self.downloadService = downloadService
        self.serverState = serverState
    }

    func loadData() async {
        let context = ModelContext(modelContainer)
        let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
        let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
        let tracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []

        displayAlbums = DownloadedAlbumMerger.merge(records: albums, tracks: tracks)

        downloadedPlaylists = playlists.map {
            DownloadedPlaylistDTO(
                id: $0.id,
                playlistId: $0.playlistId,
                serverId: $0.serverId,
                name: $0.name,
                tracksCount: $0.tracksCount,
                totalTracksCount: $0.totalTracksCount
            )
        }

        let totalBytes = tracks.map(\.fileSize).reduce(0, +)
        usedBytesFormatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    func removeAlbum(_ display: DownloadedAlbumDisplay) async {
        if display.hasFullDownloadIntent {
            try? await downloadService.remove(albumId: display.albumId, serverId: display.serverId)
        } else {
            let context = ModelContext(modelContainer)
            let aid = display.albumId
            let sid = display.serverId
            let tracks = (try? context.fetch(
                FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.albumId == aid && $0.serverId == sid })
            )) ?? []
            for track in tracks {
                try? await downloadService.remove(songId: track.songId, serverId: track.serverId)
            }
        }
        await loadData()
    }

    func removePlaylist(_ dto: DownloadedPlaylistDTO) async {
        try? await downloadService.remove(playlistId: dto.playlistId, serverId: dto.serverId)
        await loadData()
    }

    func clearAll() async {
        isClearingAll = true
        let context = ModelContext(modelContainer)
        let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
        for album in albums {
            try? await downloadService.remove(albumId: album.albumId, serverId: album.serverId)
        }
        // Remove any tracks not associated with an album record.
        let remaining = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
        for track in remaining {
            try? await downloadService.remove(songId: track.songId, serverId: track.serverId)
        }
        await loadData()
        isClearingAll = false
    }
}
