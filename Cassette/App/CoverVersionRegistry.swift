// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Observation

/// Per-cover "generation" counter — the SINGLE cover-refresh signal.
///
/// The propagation problem it solves: `CoverArtView` resolves its image once per `(loadingEnabled, id)` and
/// keeps it in `@State`; it deliberately does NOT observe the image cache in its body. So when a playlist's
/// cover changes (re-pick / first-track derivation / upload), the cache is correctly invalidated but already-
/// mounted `CoverArtView`s never re-read it — their `id` is unchanged, so their load task never re-fires.
///
/// Fix: the SHARED cover-apply path (`PlaylistCoverManager.cacheLocally`) bumps the changed id's version here,
/// and every `CoverArtView` folds `version(for: id)` into its load-task key. A bump therefore re-resolves the
/// freshly-cached cover on EVERY surface at once — no per-surface `.id()` hacks, and the bump living in the
/// shared apply means all three change paths (and both platforms) emit it consistently.
///
/// `@MainActor` + `@Observable` so SwiftUI views react; one instance lives in `AppContainer` and is injected
/// into the environment alongside `ArtworkImageCache`.
@MainActor
@Observable
final class CoverVersionRegistry {
    private var versions: [String: Int] = [:]

    /// The current generation for an id (0 until first bumped). Reading this in a view body subscribes it.
    func version(for id: String) -> Int { versions[id] ?? 0 }

    /// Mark an id's cover as changed — bumps its generation so every observing `CoverArtView` re-resolves.
    func bump(_ id: String) { versions[id, default: 0] += 1 }
}
