// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Observation

/// A global cover "generation" counter — the SINGLE cover-refresh signal.
///
/// The propagation problem it solves: `CoverArtView` resolves its image once per `(loadingEnabled, id)` and
/// keeps it in `@State`; it deliberately does NOT observe the image cache in its body. So when a playlist's
/// cover changes (re-pick / first-track derivation / upload), the cache is correctly invalidated but already-
/// mounted `CoverArtView`s never re-read it — their `id` is unchanged, so their load task never re-fires.
///
/// Fix: the SHARED cover-apply path (`PlaylistCoverManager.cacheLocally`) bumps this counter, and every
/// `CoverArtView` folds `generation` into its load-task key, so a bump re-resolves the freshly-cached cover on
/// EVERY surface at once — no per-surface `.id()` hacks, and the bump living in the shared apply means all
/// three change paths (and both platforms) emit it consistently.
///
/// GLOBAL (not per-id) on purpose: a surface can refer to a playlist cover under several ids (playlistId, the
/// server `coverArt`, a stored pinned id), so a per-id bump misses surfaces keyed by a different id. A global
/// bump re-resolves every CoverArtView — they almost all hit the warm RAM cache, so the cost is negligible and
/// only the genuinely-changed cover decodes anew. This mirrors the old global `@AppStorage` counter, which
/// worked, but applied universally inside `CoverArtView` instead of via per-surface `.id()` hacks.
///
/// `@MainActor` + `@Observable` so SwiftUI views react; one instance lives in `AppContainer` and is injected
/// into the environment alongside `ArtworkImageCache`.
@MainActor
@Observable
final class CoverVersionRegistry {
    /// Bumped on any cover change. Reading this in a view body subscribes it.
    private(set) var generation: Int = 0

    /// Mark a cover as changed — every observing `CoverArtView` re-resolves.
    func bump() { generation += 1 }
}
