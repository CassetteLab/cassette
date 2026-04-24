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

protocol DownloadServiceProtocol: AnyObject, Sendable {
    /// Live stream of in-progress downloads for UI progress display.
    var progressStream: AsyncStream<[DownloadProgress]> { get }

    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL?
    func isDownloaded(songId: String, serverId: UUID) async -> Bool
    /// Returns all song IDs that have been fully downloaded for a given server.
    func downloadedSongIds(serverId: UUID) async -> Set<String>

    /// Returns the local file URL for a downloaded cover art, or nil if not cached.
    func localCoverArtURL(forId coverArtId: String) async -> URL?

    // TODO(v1.x): switch to background URLSession with resume support.
    // v1 uses foreground URLSession — user must keep the app open during download.
    func download(song: Song, serverId: UUID) async throws
    func download(album: AlbumID3, serverId: UUID) async throws
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws

    func cancelDownload(songId: String, serverId: UUID) async
    func remove(songId: String, serverId: UUID) async throws
    func remove(albumId: String, serverId: UUID) async throws
    func remove(playlistId: String, serverId: UUID) async throws
}
