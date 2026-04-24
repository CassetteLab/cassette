// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

/// Single entry point for obtaining a playable URL for a given song.
/// Resolution order: downloaded → cached → stream.
/// PlayerService always calls this — it never contacts SwiftSonic directly.
actor MediaResolver: MediaResolverProtocol {
    private let downloadService: any DownloadServiceProtocol
    private let cacheService: any CacheServiceProtocol
    private let serverService: any ServerServiceProtocol

    init(
        downloadService: any DownloadServiceProtocol,
        cacheService: any CacheServiceProtocol,
        serverService: any ServerServiceProtocol
    ) {
        self.downloadService = downloadService
        self.cacheService = cacheService
        self.serverService = serverService
    }

    func resolve(songId: String, serverId: UUID) async throws -> MediaSource {
        // 1. Permanent download — always preferred, works offline.
        if let url = await downloadService.downloadedURL(forSongId: songId, serverId: serverId) {
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' from permanent download.")
            return .downloaded(url)
        }

        // 2. Ephemeral cache — no network needed, bump LRU clock.
        if let url = await cacheService.cachedURL(forSongId: songId, serverId: serverId) {
            await cacheService.touch(songId: songId, serverId: serverId)
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' from cache.")
            return .cached(url)
        }

        // 3. Stream. Custom headers injected so AVPlayer reaches Cloudflare-protected hosts.
        // AVURLAssetHTTPHeaderFieldsKey is used at the PlayerService call site.
        // TODO(v1.x): trigger background cache write alongside the stream.
        let client = try await serverService.makeSwiftSonicClient()
        guard let streamURL = client.streamURL(id: songId) else {
            throw CassetteError.mediaNotFound(songId: songId)
        }
        let creds = try await serverService.activeCredentials()
        Logger.resolver.debug("Resolved '\(songId, privacy: .public)' as stream.")
        return .stream(streamURL, customHeaders: creds.customHeaders)
    }
}
