// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

/// Creates public share links through the server's own `createShare` endpoint.
///
/// The link is a capability: anyone holding it can play the media without an account. It is
/// therefore never logged, the same way credentials never are — only the share id is.
actor ShareService: ShareServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private var cachedClient: SwiftSonicClient?
    private var cachedServerId: UUID?

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    // MARK: - Client

    private func client() async throws -> SwiftSonicClient {
        let activeId = await MainActor.run { serverService.state.activeServer?.id }
        if let cached = cachedClient, cachedServerId == activeId, activeId != nil {
            return cached
        }
        let fresh = try await serverService.makeSwiftSonicClient()
        cachedClient = fresh
        cachedServerId = activeId
        return fresh
    }

    // MARK: - Create

    func createPublicLink(songIds: [String], description: String? = nil) async throws -> URL {
        guard !songIds.isEmpty else { throw ShareLinkError.other }
        do {
            let shares = try await client().createShare(ids: songIds, description: description)
            guard let share = shares.first, let url = URL(string: share.url) else {
                Logger.share.error("createShare returned no usable share.")
                throw ShareLinkError.other
            }
            Logger.share.info(
                "Created share \(share.id, privacy: .public) for \(songIds.count, privacy: .public) item(s)."
            )
            return url
        } catch {
            let mapped = ShareLinkError(error)
            Logger.share.error("createShare failed: \(String(describing: mapped), privacy: .public)")
            throw mapped
        }
    }
}
