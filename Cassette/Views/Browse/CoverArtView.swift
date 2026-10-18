// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - WARNING — do NOT read from ArtworkImageCache in CoverArtView.body
//
// ArtworkImageCache is @Observable. Any property access in a view's body creates
// an observation dependency on the WHOLE cache dictionary — not just the one key
// being read. When any cover arrives (i.e., cache[key] = image), every CoverArtView
// whose body observed the dictionary is invalidated and re-evaluated.
//
// With N history rows × M covers loading = N×M body re-evaluations. At 13 rows ×
// 13 covers = 169 redundant body calls on search open, cascading into parent list
// re-renders. Measured as ~20 consecutive SearchHistoryListView.body re-renders.
//
// The fix: never read artworkCache in CoverArtView.body. CoverArtViewContent owns
// @State private var cachedImage and a .task that loads exactly one id. Only THAT
// view's body re-renders when its own @State changes — cache mutations for other ids
// are invisible to it.

/// Async cover art loader. Resolves via ArtworkImageCache (RAM → disk → network).
/// Falls back to the URL/AsyncImage path only if ArtworkImageCache fails entirely.
/// Use `CoverArtCard` in views — it wraps this with clip, shadow, and border handling.
///
/// - Parameters:
///   - size: Requested pixel size, used for the AsyncImage fallback URL only.
///           Tier is auto-detected: `< 160` → `.thumb` (240 px), `< 480` → `.grid` (600 px),
///           otherwise `.hero` (1200 px).
///   - tier: Optional explicit tier override. Pass `.hero` for detail-view hero images
///           whose pixel size is below 480 (e.g. macOS DetailHeroView at 280 px).
struct CoverArtView: View {
    let id: String
    let size: Int?
    var tier: ArtworkTier? = nil
    var cornerRadius: CGFloat = 0
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil
    /// When false, the artwork load is deferred (placeholder/initial image only) until it flips true —
    /// used to avoid firing artwork tasks for rows mounted but not yet visible (e.g. the inline queue at
    /// opacity 0). Defaults to true so every other call site is unchanged.
    var loadingEnabled: Bool = true

    var body: some View {
        // No artworkCache read here — see guard comment above.
        // CoverArtViewContent's .task handles the initial RAM check without creating
        // an @Observable observation dependency.
        CoverArtViewContent(
            id: id,
            size: size,
            tier: tier,
            cornerRadius: cornerRadius,
            placeholderSystemImage: placeholderSystemImage,
            initialImage: initialImage,
            loadingEnabled: loadingEnabled
        )
    }
}

// MARK: - Content

private struct CoverArtViewContent: View {
    let id: String
    let size: Int?
    let tier: ArtworkTier?
    let cornerRadius: CGFloat
    let placeholderSystemImage: String
    let loadingEnabled: Bool

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkCache
    /// Global cover-refresh counter (UserDefaults-backed → reliably observed, no @Observable-in-body / optional-
    /// @Environment pitfalls). Bumped by PlaylistCoverManager on any cover change; folded into the load-task key
    /// so a cover change re-resolves the freshly-cached cover on EVERY surface (incl. Home Pinned).
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0
    @State private var cachedImage: PlatformImage?
    @State private var url: URL?
    /// The id whose image `cachedImage` currently represents. Lets a track change resolve the
    /// NEW id instead of short-circuiting on a stale image: we only keep the current image when
    /// `displayedId == id`. A failed hero load can therefore never leave the previous track's
    /// artwork on screen — the resolution below clears it and falls back against the current id.
    @State private var displayedId: String?

    init(id: String, size: Int?, tier: ArtworkTier?, cornerRadius: CGFloat, placeholderSystemImage: String, initialImage: PlatformImage?, loadingEnabled: Bool = true) {
        self.id = id
        self.size = size
        self.tier = tier
        self.cornerRadius = cornerRadius
        self.placeholderSystemImage = placeholderSystemImage
        self.loadingEnabled = loadingEnabled
        _cachedImage = State(initialValue: initialImage)
        // A caller-provided image is its best guess for THIS id, so mark it displayed for `id`:
        // it is upgraded by the load step online, but kept (not cleared) when offline.
        _displayedId = State(initialValue: initialImage == nil ? nil : id)
    }

    /// Callers pass `size` as roughly twice the point size they display at — a convention from
    /// when screens were @2x. It is left alone deliberately: raising it to the real @3x scale
    /// would push every grid cell past the hero threshold and decode 1200 px for a 180pt tile.
    /// The tiers absorb the difference instead.
    private var resolvedTier: ArtworkTier {
        if let tier { return tier }
        switch size ?? 0 {
        case ..<160: return .thumb   // rows and avatars: 44–64pt, 192 px at @3x
        case ..<480: return .grid    // grid cells: 90–180pt, up to 540 px at @3x
        default: return .hero
        }
    }

    var body: some View {
        ZStack {
            if let cached = cachedImage {
                Image(platformImage: cached)
                    .resizable()
                    .scaledToFill()
            } else {
                // AsyncImage safety fallback — reached only when artworkCache.load() fails.
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        GeometryReader { geo in
                            SkeletonBlock(
                                width: geo.size.width,
                                height: geo.size.height,
                                cornerRadius: cornerRadius
                            )
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        // Keyed on (loadingEnabled, id) so deferring/undeferring re-runs the load: a deferred row shows its
        // placeholder/initial image and fires NO artwork task until it becomes visible (loadingEnabled flips).
        .task(id: "\(loadingEnabled):\(id):\(coverArtUploadVersion)") {
            guard loadingEnabled else { return }
            url = nil
            let t = resolvedTier
            let online = container?.serverState.isOnline ?? true

            // Resolution runs against the CURRENT id only; each successful step sets both
            // `cachedImage` and `displayedId = id`, so an image whose id != current id is never
            // shown. The previous image stays visible while we resolve (no flash) — it is only
            // swapped atomically on success, or cleared at the end if nothing resolves.

            // 1. RAM hit for the requested tier. Sync read in .task (not body) — reads in task
            //    closures are not tracked by @Observable, so this creates no observation on the
            //    global cache dictionary.
            if let ram = artworkCache.cachedImage(for: id, tier: t) {
                apply(ram, for: id)
                return
            }

            // Reuse another cached size immediately while the requested tier loads. This writes
            // `displayedId = id`, so the "already correct for this id" guard below would otherwise
            // read it as a finished resolution and skip the disk fallbacks — leaving a thumb on
            // screen while a hero sits on disk. The flag keeps the two states apart.
            var showingOtherTier = false
            if displayedId != id, let ram = artworkCache.cachedImage(for: id) {
                apply(ram, for: id)
                showingOtherTier = true
            }

            // 2. Tiered load (RAM → disk `{id}@{tier}` → network). Network is online-only — offline
            //    we skip straight to the local fallbacks rather than wait on a doomed fetch.
            if online, let image = await artworkCache.load(coverArtId: id, tier: t) {
                guard !Task.isCancelled else { return }
                apply(image, for: id)
                return
            }

            // The image already on screen is correct for this id (a caller-provided initialImage,
            // or an unchanged id) — keep it rather than fall back to a lower tier or clear it.
            // A stand-in from another tier does not count: a better one may still be on disk.
            if displayedId == id, !showingOtherTier { return }

            // 3. Decode a local file off-main, including the grid tier if no hero or download exists.
            if let image = await artworkCache.localImage(for: id, tier: t) {
                guard !Task.isCancelled else { return }
                apply(image, for: id)
                return
            }
            guard !Task.isCancelled else { return }

            // 4. Nothing local resolved. Clear the image only when it belongs to a PREVIOUS id —
            //    a stand-in from another tier is this track's own cover, just not at the requested
            //    size, and wiping it would trade a slightly soft cover for an empty square.
            if !showingOtherTier {
                cachedImage = nil
                displayedId = nil
            }
            let fallbackURL = await container?.libraryService.coverArtURL(id: id, size: size)
            guard !Task.isCancelled else { return }
            url = fallbackURL
        }
    }

    /// Atomically swaps in a resolved image and records the id it belongs to.
    private func apply(_ image: PlatformImage, for resolvedId: String) {
        cachedImage = image
        displayedId = resolvedId
        url = nil
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [CassetteColors.accent.opacity(0.25), CassetteColors.accent.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: placeholderSystemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
