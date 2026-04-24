import Foundation
import SwiftData

@Model
final class CachedTrack {
    var id: UUID
    var songId: String
    var serverId: UUID
    var filePath: String        // relative to Caches/app.cassette/audio/
    var fileSize: Int64
    var mimeType: String
    var cachedAt: Date
    var expiresAt: Date         // cachedAt + configurable TTL
    var lastAccessedAt: Date    // updated on each play → LRU eviction key

    init(
        id: UUID = UUID(),
        songId: String,
        serverId: UUID,
        filePath: String,
        fileSize: Int64,
        mimeType: String,
        cachedAt: Date = Date(),
        expiresAt: Date,
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.songId = songId
        self.serverId = serverId
        self.filePath = filePath
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
        self.lastAccessedAt = lastAccessedAt
    }
}
