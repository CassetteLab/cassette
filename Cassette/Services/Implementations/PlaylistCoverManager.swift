// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

/// Applies a playlist cover (a generated gradient or a photo) consistently across servers:
/// 1. encode/render a square JPEG,
/// 2. cache it on-device under the tier keys `CoverArtView` reads, so EVERY on-device surface (detail +
///    cards) shows it — Navidrome or not, and
/// 3. best-effort upload it to Navidrome for the real cross-device server cover.
///
/// On a non-Navidrome server (or offline) the upload simply fails and is swallowed — the local cache stands
/// (on-device cohesion; cross-device shows the placeholder, which is expected and unavoidable without an
/// upload endpoint). Cross-platform — the only platform-specific code is the renderer's JPEG bridge.
@MainActor
struct PlaylistCoverManager {
    private let serverState: ServerState
    private let serverService: any ServerServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let artworkImageCache: ArtworkImageCache
    private let coverVersionRegistry: CoverVersionRegistry

    init(
        serverState: ServerState,
        serverService: any ServerServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        artworkImageCache: ArtworkImageCache,
        coverVersionRegistry: CoverVersionRegistry
    ) {
        self.serverState = serverState
        self.serverService = serverService
        self.downloadService = downloadService
        self.artworkImageCache = artworkImageCache
        self.coverVersionRegistry = coverVersionRegistry
    }

    /// Render a gradient spec → JPEG, cache it on-device, best-effort upload. Returns the JPEG bytes.
    @discardableResult
    func applyGradientCover(_ spec: PlaylistGradientSpec, playlistId: String) async -> Data? {
        guard let data = PlaylistGradientRenderer.jpegData(for: spec) else {
            Logger.playlist.warning("PlaylistCoverManager: gradient render produced no data")
            return nil
        }
        await applyImageCover(data, playlistId: playlistId)
        return data
    }

    /// Cache a (photo or rendered) JPEG on-device + best-effort upload to Navidrome.
    func applyImageCover(_ jpegData: Data, playlistId: String) async {
        await cacheLocally(jpegData, playlistId: playlistId)
        await uploadIfPossible(jpegData, playlistId: playlistId)
    }

    private func cacheLocally(_ data: Data, playlistId: String) async {
        // Invalidate FIRST — it deletes the tier disk files and clears RAM; persisting first would let the
        // invalidate wipe what we just wrote. Then persist under BOTH tier keys, because load() reads only
        // `{id}@{tier}` (never the untagged `{id}`, which is swept on launch).
        await artworkImageCache.invalidate(for: playlistId)
        for tier in [ArtworkTier.thumb, .hero] {
            await downloadService.persistCover(data, forId: "\(playlistId)@\(tier.rawValue)")
        }
        // The SINGLE cross-surface refresh signal: bumping here (the shared apply path) means all three change
        // paths — re-pick, first-track derivation, upload — and both platforms emit it consistently, and every
        // CoverArtView folding `generation` into its task key re-resolves the freshly-cached cover.
        coverVersionRegistry.bump()
    }

    private func uploadIfPossible(_ jpegData: Data, playlistId: String) async {
        guard let snapshot = serverState.activeServer,
              let baseURL = URL(string: snapshot.baseURL) else { return }
        do {
            let creds = try await serverService.activeCredentials()
            let api = NavidromeNativeAPI(transport: CustomHeadersTransport(headers: creds.customHeaders))
            let token = try await api.authenticate(
                baseURL: baseURL,
                username: snapshot.username,
                password: creds.password
            )
            try await api.uploadPlaylistCover(
                baseURL: baseURL,
                token: token,
                playlistId: playlistId,
                imageData: jpegData,
                mimeType: "image/jpeg"
            )
            Logger.playlist.debug("PlaylistCoverManager: uploaded cover for \(playlistId, privacy: .public)")
        } catch {
            // Non-Navidrome server or offline — upload is impossible; the on-device cache already stands.
            Logger.playlist.warning("PlaylistCoverManager: cover upload skipped (local cache stands): \(error)")
        }
    }
}
