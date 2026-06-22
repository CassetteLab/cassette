// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Resolves a gradient cover spec for a chosen form by deriving its base color from a playlist's FIRST
/// track (the playlist's musical identity). The single source of truth for "form + content → spec", reused
/// by the edit flow (re-pick) and the empty→first-track transition. Cross-platform.
///
/// - `firstTrackCoverArtId == nil` (empty playlist) → the neutral default spec.
/// - otherwise → the first track cover's dominant color (averaged OFF-MAIN so a resolve never hitches the
///   UI), memoized via `DominantColorExtractor`.
///
/// Callers FREEZE the result into `PlaylistCoverChoice`; this is never re-run on reorder/remove/track-1
/// change — only on an explicit re-pick or the one-time empty→first-track transition.
@MainActor
enum PlaylistGradientResolver {
    static func resolve(
        form: PlaylistGradientShape,
        firstTrackCoverArtId: String?,
        artworkImageCache: ArtworkImageCache,
        colorExtractor: DominantColorExtractor
    ) async -> PlaylistGradientSpec {
        guard let coverArtId = firstTrackCoverArtId else {
            return .neutral(shape: form)
        }
        if let cached = colorExtractor.cachedColor(for: coverArtId), cached != .clear {
            // Vibrance-boost the DERIVED (averaged, muddy) color so the gradient pops; baked into the frozen
            // spec, so it propagates to the crisp hero + the JPEG. The neutral/brand-default path is untouched.
            return PlaylistGradientSpec(shape: form, baseColor: cached.vibranceBoosted())
        }
        guard let image = await artworkImageCache.load(coverArtId: coverArtId, tier: .thumb) else {
            return .neutral(shape: form)
        }
        let packed = await Task.detached(priority: .userInitiated) {
            DominantColorExtractor.packedAverageColor(from: image)
        }.value
        guard let packed else { return .neutral(shape: form) }
        let color = colorExtractor.storeColor(packed: packed, for: coverArtId)
        return color == .clear ? .neutral(shape: form) : PlaylistGradientSpec(shape: form, baseColor: color.vibranceBoosted())
    }
}
