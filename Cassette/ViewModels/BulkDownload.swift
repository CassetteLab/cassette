// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
import SwiftSonic

/// Bounded fan-out behind the "download everything in this list" actions (Songs, Favorites).
///
/// This is deliberately *not* a second download pipeline: every track still goes through
/// `DownloadServiceProtocol.download(song:serverId:)`, which stays the only writer of downloaded
/// state, skips what is already on disk and de-duplicates in-flight tasks. All this adds is the
/// same concurrency ceiling `DownloadService.download(album:)` already applies to its own
/// fan-out, so a multi-thousand-track library doesn't fire one request per song at once.
nonisolated enum BulkDownload {
    /// Mirrors `DownloadService.download(album:)`'s own limit — one ceiling across the app.
    static let maxConcurrent = 3

    /// Above this many *remaining* tracks, callers confirm before queueing. Counted on what is
    /// left to fetch rather than the list size, so re-opening a mostly-downloaded library
    /// doesn't nag about work that won't happen.
    static let confirmationThreshold = 150

    /// The subset of `songs` not already on disk, in list order.
    static func missing(from songs: [Song], downloadedIds: Set<String>) -> [Song] {
        songs.filter { !downloadedIds.contains($0.id) }
    }

    /// Downloads `songs`, at most `maxConcurrent` at a time. Returns how many succeeded; a single
    /// track's failure is logged and skipped so one bad file can't abort the whole batch.
    @discardableResult
    static func run(
        _ songs: [Song],
        serverId: UUID,
        using service: any DownloadServiceProtocol
    ) async -> Int {
        guard !songs.isEmpty else { return 0 }
        var succeeded = 0
        await withTaskGroup(of: Bool.self) { group in
            var iterator = songs.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let song = iterator.next() else { break }
                group.addTask { await attempt(song, serverId: serverId, using: service) }
            }
            // Refill as each finishes, keeping at most `maxConcurrent` requests in flight.
            for await didSucceed in group {
                if didSucceed { succeeded += 1 }
                if let song = iterator.next() {
                    group.addTask { await attempt(song, serverId: serverId, using: service) }
                }
            }
        }
        Logger.download.info("Bulk download finished — \(succeeded, privacy: .public)/\(songs.count, privacy: .public) tracks")
        return succeeded
    }

    private static func attempt(
        _ song: Song,
        serverId: UUID,
        using service: any DownloadServiceProtocol
    ) async -> Bool {
        do {
            try await service.download(song: song, serverId: serverId)
            return true
        } catch {
            Logger.download.error("Bulk download failed for '\(song.id, privacy: .public)': \(error, privacy: .public)")
            return false
        }
    }
}
