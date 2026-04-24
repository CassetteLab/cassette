import Foundation
import SwiftData
import OSLog

// TODO(v1.x): replace download-alongside-stream approach with AVAssetResourceLoaderDelegate
// chunk interception for true in-flight caching. Deferred because AVAssetResourceLoaderDelegate
// requires careful handling of byte-range requests, partial content, and seek resumption.
actor CacheService: CacheServiceProtocol {
    private let modelContainer: ModelContainer
    private let cacheDirectory: URL

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("app.cassette/audio", isDirectory: true)
    }

    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL? {
        // TODO: implement in Étape 5
        return nil
    }

    func store(data: Data, forSongId songId: String, serverId: UUID, mimeType: String) async throws -> URL {
        // TODO: implement in Étape 5
        throw CassetteError.notImplemented
    }

    func touch(songId: String, serverId: UUID) async {
        // TODO: implement in Étape 5
    }

    func evictExpired() async {
        // TODO: implement in Étape 5
    }

    func evictLRU(toFitQuota quotaBytes: Int64) async {
        // TODO: implement in Étape 5
    }

    func invalidate(songId: String, serverId: UUID) async {
        // TODO: implement in Étape 5
    }

    var usedBytes: Int64 {
        // TODO: implement in Étape 5
        return 0
    }
}
