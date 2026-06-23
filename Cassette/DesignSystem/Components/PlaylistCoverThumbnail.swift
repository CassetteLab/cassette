// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Rebrand playlist cover thumbnail for the library surfaces (iOS). A user-picked GRADIENT cover renders LIVE
/// (the static `PlaylistGradientView` + the title drawn on the gradient — the `PlaylistCoverCarousel` look) so
/// it matches the editor and follows re-picks/derivation; a PHOTO or server cover stays RASTER (`CoverArtView`,
/// no title). 12pt continuous corners.
///
/// The gradient choice is re-read in a `.task` keyed on the shared cover-version bump (`coverArtUploadVersion`)
/// — the SAME signal every cover change already emits via `PlaylistCoverManager` — so a re-pick / first-track
/// derivation refreshes the thumbnail without pulling a reactive `@Query`/`@Model` into the cell's view tree
/// (which the codebase avoids for scroll perf). The live gradient is animation-free (static GPU shader), so N
/// cells do not hitch.
///
/// macOS keeps the OLD raster card (Phase 5) — the live-gradient treatment is iOS-only; the macOS branch is a
/// plain raster `CoverArtView` so the macOS rendering is unchanged.
struct PlaylistCoverThumbnail: View {
    let playlistId: String
    let serverId: UUID?
    /// Cover id for the RASTER (photo / server) path — used when there is no user-picked gradient (and on macOS).
    let coverArtId: String
    let title: String
    let size: CGFloat

    #if os(iOS)
    @Environment(\.appContainer) private var container
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0
    @State private var spec: PlaylistGradientSpec?
    #endif

    var body: some View {
        #if os(iOS)
        iosBody
        #else
        // macOS keeps the old raster card (Phase 5) — no live gradient, no rebrand corners.
        CoverArtView(id: coverArtId, size: Int(size * 2))
            .frame(width: size, height: size)
            .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        ZStack {
            if let spec {
                PlaylistGradientView(spec: spec)
                titleOverlay
            } else {
                CoverArtView(id: coverArtId, size: Int(size * 2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        .task(id: "\(playlistId):\(serverId?.uuidString ?? "-"):\(coverArtUploadVersion)") {
            spec = resolveSpec()
        }
    }

    /// Re-read the stored user-picked gradient spec (nil → photo/server, raster path). Driven by the cover-
    /// version bump so re-pick / first-track derivation re-resolve. A plain main-context fetch (fetchLimit 1),
    /// mirroring PlaylistDetailView's gradient-spec resolution.
    private func resolveSpec() -> PlaylistGradientSpec? {
        guard let container else { return nil }
        // Caller-provided serverId (downloaded/pinned models carry their own); else the active server.
        guard let sid = serverId ?? container.serverState.activeServer?.id else { return nil }
        let choice = PlaylistCoverStore(modelContainer: container.modelContainer)
            .choice(playlistId: playlistId, serverId: sid)
        return choice?.isUserPicked == true ? choice?.spec : nil
    }

    /// The live title on the gradient — the PlaylistCoverCarousel look (white, bold, rounded, top-leading,
    /// shadowed), scaled to the thumbnail size.
    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: size * 0.15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: 1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(size * 0.09)
    }
    #endif
}
