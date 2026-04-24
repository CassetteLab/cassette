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

    // TODO(v1.x): switch both methods to background URLSession with resume support.
    // v1 uses foreground URLSession — user must keep the app open during download.
    func download(song: Song, serverId: UUID) async throws
    func download(albumId: String, serverId: UUID) async throws

    func cancelDownload(songId: String, serverId: UUID) async
    func remove(songId: String, serverId: UUID) async throws
    func remove(albumId: String, serverId: UUID) async throws
}
