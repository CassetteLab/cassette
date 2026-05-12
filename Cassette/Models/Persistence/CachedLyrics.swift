// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

// TODO(v1.x): consider TTL or LRU eviction if storage grows.
@Model
final class CachedLyrics {
    @Attribute(.unique) var compositeKey: String  // "{serverId}:{songId}"
    var songId: String
    var serverId: UUID
    var jsonPayload: Data  // serialized LyricsList — see LyricsEncoding.swift for Encodable conformance
    var fetchedAt: Date

    init(songId: String, serverId: UUID, jsonPayload: Data) {
        self.compositeKey = "\(serverId.uuidString):\(songId)"
        self.songId = songId
        self.serverId = serverId
        self.jsonPayload = jsonPayload
        self.fetchedAt = Date()
    }
}
