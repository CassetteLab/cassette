// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

nonisolated struct DownloadProgress: Sendable {
    let songId: String
    let serverId: UUID
    let progress: Double    // 0.0 → 1.0
    let totalBytes: Int64?
    let receivedBytes: Int64
}

nonisolated struct LocalAlbumData: Sendable {
    let albumId: String
    let albumName: String
    let artistName: String?
    let coverArtId: String?
    let songs: [DisplayableSong]
}

nonisolated struct LocalPlaylistData: Sendable {
    let playlistId: String
    let name: String
    let coverArtId: String?
    let songs: [DisplayableSong]
}

protocol DownloadServiceProtocol: AnyObject, Sendable {
    /// Live stream of in-progress downloads for UI progress display.
    var progressStream: AsyncStream<[DownloadProgress]> { get }

    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL?
    func isDownloaded(songId: String, serverId: UUID) async -> Bool
    /// Returns all song IDs that have been fully downloaded for a given server.
    func downloadedSongIds(serverId: UUID) async -> Set<String>

    /// Returns the local file URL for a downloaded cover art, or nil if not cached.
    func localCoverArtURL(forId coverArtId: String) async -> URL?

    /// Persists cover image data to the shared cover art directory (best-effort, errors are logged).
    func persistCover(_ data: Data, forId coverArtId: String) async

    /// Removes the cached cover art file for the given ID. No-op if not on disk.
    func removeCover(forId coverArtId: String) async

    /// Deletes orphaned cover files whose name is not in `referencedIds`. Returns count deleted.
    @discardableResult
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int

    /// Returns offline-playable album data assembled from persisted tracks, or nil if not downloaded.
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData?
    /// Returns offline-playable playlist data assembled from persisted tracks, or nil if not downloaded.
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData?

    // TODO(v1.x): switch to background URLSession with resume support.
    // v1 uses foreground URLSession — user must keep the app open during download.
    func download(song: Song, serverId: UUID) async throws
    func download(album: AlbumID3, serverId: UUID) async throws
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws

    /// Returns `true` if a download task is currently in-flight for this song.
    func isDownloading(songId: String, serverId: UUID) async -> Bool
    func isDownloadingAlbum(_ albumId: String) async -> Bool
    func isDownloadingPlaylist(_ playlistId: String) async -> Bool
    func cancelDownload(songId: String, serverId: UUID) async
    func remove(songId: String, serverId: UUID) async throws
    func remove(albumId: String, serverId: UUID) async throws
    func remove(playlistId: String, serverId: UUID) async throws
}
