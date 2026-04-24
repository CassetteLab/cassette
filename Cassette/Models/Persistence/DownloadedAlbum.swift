import Foundation
import SwiftData

@Model
final class DownloadedAlbum {
    var id: UUID
    var albumId: String
    var serverId: UUID
    var name: String
    var artist: String?
    var tracksCount: Int
    var downloadedAt: Date
    var coverArtId: String?

    init(
        id: UUID = UUID(),
        albumId: String,
        serverId: UUID,
        name: String,
        artist: String? = nil,
        tracksCount: Int,
        downloadedAt: Date = Date(),
        coverArtId: String? = nil
    ) {
        self.id = id
        self.albumId = albumId
        self.serverId = serverId
        self.name = name
        self.artist = artist
        self.tracksCount = tracksCount
        self.downloadedAt = downloadedAt
        self.coverArtId = coverArtId
    }
}
