// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

protocol CacheServiceProtocol: AnyObject, Sendable {
    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL?

    func store(
        data: Data,
        forSongId songId: String,
        serverId: UUID,
        mimeType: String
    ) async throws -> URL

    /// Updates lastAccessedAt for LRU tracking. Call whenever a cached track is played.
    func touch(songId: String, serverId: UUID) async

    func evictExpired() async
    func evictLRU(toFitQuota quotaBytes: Int64) async
    func invalidate(songId: String, serverId: UUID) async

    var usedBytes: Int64 { get async }
}
