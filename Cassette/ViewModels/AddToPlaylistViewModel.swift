// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

enum AddToPlaylistResult {
    case added
    case duplicate
    case failed
}

@MainActor
@Observable
final class AddToPlaylistViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var addingToPlaylistIds: Set<String> = []

    private let song: DisplayableSong
    private let playlistService: any PlaylistServiceProtocol
    private let toastService: ToastService

    init(song: DisplayableSong, playlistService: any PlaylistServiceProtocol, toastService: ToastService) {
        self.song = song
        self.playlistService = playlistService
        self.toastService = toastService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playlists = try await playlistService.listPlaylists()
        } catch {
            Logger.playlist.error("AddToPlaylistViewModel: failed to load playlists: \(error)")
        }
    }

    /// Checks for a duplicate then adds. Returns `.duplicate` if the song is already in the
    /// playlist (caller shows confirmation), `.added` on success, `.failed` on error.
    func checkAndAdd(to playlist: Playlist) async -> AddToPlaylistResult {
        guard !addingToPlaylistIds.contains(playlist.id) else { return .failed }
        addingToPlaylistIds.insert(playlist.id)
        defer { addingToPlaylistIds.remove(playlist.id) }

        do {
            let detail = try await playlistService.getPlaylist(id: playlist.id)
            let alreadyIn = detail.entry?.contains { $0.id == song.id } ?? false
            if alreadyIn { return .duplicate }
        } catch {
            Logger.playlist.error("AddToPlaylistViewModel: duplicate check failed for playlist \(playlist.id): \(error)")
            // Fallback: proceed with add
        }

        return await performAdd(to: playlist)
    }

    /// Adds without a duplicate check — used after the user confirms "Add Anyway",
    /// or when adding to a newly-created (empty) playlist.
    @discardableResult
    func forceAdd(to playlist: Playlist) async -> Bool {
        guard !addingToPlaylistIds.contains(playlist.id) else { return false }
        addingToPlaylistIds.insert(playlist.id)
        defer { addingToPlaylistIds.remove(playlist.id) }
        return await performAdd(to: playlist) == .added
    }

    func handleNewPlaylistCreated(_ created: PlaylistWithSongs) async -> Bool {
        let summary = Playlist(
            id: created.id,
            name: created.name,
            songCount: created.songCount,
            duration: created.duration,
            comment: created.comment,
            owner: created.owner,
            isPublic: created.isPublic,
            created: created.created,
            changed: created.changed,
            coverArt: created.coverArt
        )
        playlists.insert(summary, at: 0)
        return await forceAdd(to: summary)
    }

    // MARK: - Private

    private func performAdd(to playlist: Playlist) async -> AddToPlaylistResult {
        let songId = song.id
        let songObj = song.asSong()
        do {
            try await playlistService.addTracks(playlistId: playlist.id, songs: [songObj])
            toastService.showSuccess("Added to \"\(playlist.name)\"")
            return .added
        } catch {
            Logger.playlist.error("AddToPlaylistViewModel: failed to add song \(songId) to playlist \(playlist.id): \(error)")
            toastService.showError("Failed to add to \(playlist.name)")
            return .failed
        }
    }
}

private extension DisplayableSong {
    func asSong() -> Song {
        Song(
            id: id,
            title: title,
            parent: nil,
            isDir: false,
            album: albumName,
            artist: artist,
            track: trackNumber,
            year: nil,
            genre: nil,
            coverArt: coverArtId,
            size: nil,
            contentType: nil,
            suffix: audioFormat?.lowercased(),
            transcodedContentType: nil,
            transcodedSuffix: nil,
            duration: duration > 0 ? Int(duration) : nil,
            bitRate: nil,
            path: nil,
            isVideo: false,
            userRating: nil,
            averageRating: nil,
            playCount: nil,
            discNumber: nil,
            created: nil,
            starred: nil,
            albumId: nil,
            artistId: nil,
            type: nil
        )
    }
}
