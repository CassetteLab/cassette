// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

protocol CacheServiceProtocol: AnyObject, Sendable {
    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL?

    /// Stores audio data on disk and records it in SwiftData.
    /// `ttl` controls the expiry window; pass `CacheSettings.ttl` at the call site so this
    /// actor remains independent of UserDefaults/Settings infrastructure (decision A1).
    func store(
        data: Data,
        forSongId songId: String,
        serverId: UUID,
        mimeType: String,
        ttl: TimeInterval
    ) async throws -> URL

    /// Updates lastAccessedAt for LRU tracking. Call whenever a cached track is played.
    func touch(songId: String, serverId: UUID) async

    func evictExpired() async
    func evictLRU(toFitQuota quotaBytes: Int64) async

    /// Removes a single record and its file immediately (e.g. on stale-file detection).
    func invalidate(songId: String, serverId: UUID) async

    /// Deletes every cached track and file — called by "Clear cache now".
    func clearAll() async

    var usedBytes: Int64 { get async }
}
