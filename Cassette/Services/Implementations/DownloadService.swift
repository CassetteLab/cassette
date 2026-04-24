import Foundation
import SwiftData
import SwiftSonic
import OSLog

// TODO(v1.x): switch to background URLSession with resume-after-kill support.
// v1 uses foreground URLSession — the user must keep the app open during download.
actor DownloadService: DownloadServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer
    private let downloadsDirectory: URL
    private var progressContinuation: AsyncStream<[DownloadProgress]>.Continuation?

    nonisolated let progressStream: AsyncStream<[DownloadProgress]>

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer) {
        self.serverService = serverService
        self.modelContainer = modelContainer

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.downloadsDirectory = docs.appendingPathComponent("app.cassette/downloads", isDirectory: true)

        // AsyncStream.init closure is called synchronously — cont is guaranteed set before init returns.
        var cont: AsyncStream<[DownloadProgress]>.Continuation!
        progressStream = AsyncStream<[DownloadProgress]> { cont = $0 }
        progressContinuation = cont
    }

    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? {
        // TODO: implement in Étape 6
        return nil
    }

    func isDownloaded(songId: String, serverId: UUID) async -> Bool {
        // TODO: implement in Étape 6
        return false
    }

    func download(song: Song, serverId: UUID) async throws {
        // TODO(v1.x): background URLSession with resume
        // TODO: implement in Étape 6
    }

    func download(albumId: String, serverId: UUID) async throws {
        // TODO(v1.x): background URLSession with resume
        // TODO: implement in Étape 6
    }

    func cancelDownload(songId: String, serverId: UUID) async {
        // TODO: implement in Étape 6
    }

    func remove(songId: String, serverId: UUID) async throws {
        // TODO: implement in Étape 6
    }

    func remove(albumId: String, serverId: UUID) async throws {
        // TODO: implement in Étape 6
    }
}
