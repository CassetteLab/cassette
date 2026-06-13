// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
            isOffline = true
            await loadFromLocal()
        }
        isLoading = false
        isDownloadingPlaylist = await downloadService.isDownloadingPlaylist(playlistId)
    }

    private func loadFromAPI() async {
        do {
            let apiPlaylist = try await libraryService.playlist(id: playlistId)
            // Empty-success guard: behind a captive proxy / Cloudflare-WARP edge the server
            // is reachable but answers 200 with no entries. That never throws, so the catch
            // below can't help — treat an empty result exactly like a failure and prefer the
            // downloaded copy before clobbering the UI with an "Empty Playlist" state.
            if (apiPlaylist.entry ?? []).isEmpty, await loadFromLocal() { return }
            playlistDetail = apiPlaylist
            guard let serverId = serverState.activeServer?.id else { return }
            let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
            name = apiPlaylist.name
            owner = apiPlaylist.owner
            coverArtId = apiPlaylist.coverArt
            songs = (apiPlaylist.entry ?? []).map { DisplayableSong(from: $0, isDownloaded: downloadedIds.contains($0.id)) }
            isOffline = false
            // Self-heal: if this playlist was downloaded before songIds existed (or with an
            // empty list), repair it now from the authoritative order so it reads offline next time.
            await downloadService.backfillPlaylistSongIds(
                playlistId: playlistId,
                serverId: serverId,
                orderedSongIds: (apiPlaylist.entry ?? []).map(\.id)
            )
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
              let data = await downloadService.localPlaylistData(playlistId: playlistId, serverId: serverId),
              !data.songs.isEmpty else { return false }
        name = data.name
        coverArtId = data.coverArtId
        songs = data.songs
        isOffline = true
        return true
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
                coverArtId: song.coverArtId, audioFormat: song.audioFormat,
                replayGainTrackGain: song.replayGainTrackGain,
                replayGainTrackPeak: song.replayGainTrackPeak,
                replayGainAlbumGain: song.replayGainAlbumGain,
                replayGainAlbumPeak: song.replayGainAlbumPeak,
                replayGainBaseGain: song.replayGainBaseGain,
                replayGainFallbackGain: song.replayGainFallbackGain
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
                coverArtId: s.coverArtId, audioFormat: s.audioFormat,
                replayGainTrackGain: s.replayGainTrackGain,
                replayGainTrackPeak: s.replayGainTrackPeak,
                replayGainAlbumGain: s.replayGainAlbumGain,
                replayGainAlbumPeak: s.replayGainAlbumPeak,
                replayGainBaseGain: s.replayGainBaseGain,
                replayGainFallbackGain: s.replayGainFallbackGain
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
                            coverArtId: $0.coverArtId, audioFormat: $0.audioFormat,
                            replayGainTrackGain: $0.replayGainTrackGain,
                            replayGainTrackPeak: $0.replayGainTrackPeak,
                            replayGainAlbumGain: $0.replayGainAlbumGain,
                            replayGainAlbumPeak: $0.replayGainAlbumPeak,
                            replayGainBaseGain: $0.replayGainBaseGain,
                            replayGainFallbackGain: $0.replayGainFallbackGain)
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
                            coverArtId: $0.coverArtId, audioFormat: $0.audioFormat,
                            replayGainTrackGain: $0.replayGainTrackGain,
                            replayGainTrackPeak: $0.replayGainTrackPeak,
                            replayGainAlbumGain: $0.replayGainAlbumGain,
                            replayGainAlbumPeak: $0.replayGainAlbumPeak,
                            replayGainBaseGain: $0.replayGainBaseGain,
                            replayGainFallbackGain: $0.replayGainFallbackGain)
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
