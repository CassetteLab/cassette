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
///           Tier is auto-detected: `size >= 480` → `.hero` (1200 px decode);
///           `size < 480` → `.thumb` (240 px decode).
///   - tier: Optional explicit tier override. Pass `.hero` for detail-view hero images
///           whose pixel size is below 480 (e.g. macOS DetailHeroView at 280 px).
struct CoverArtView: View {
    let id: String
    let size: Int?
    var tier: ArtworkTier? = nil
    var cornerRadius: CGFloat = 0
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil

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
            initialImage: initialImage
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

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkCache
    @State private var cachedImage: PlatformImage?
    @State private var url: URL?

    init(id: String, size: Int?, tier: ArtworkTier?, cornerRadius: CGFloat, placeholderSystemImage: String, initialImage: PlatformImage?) {
        self.id = id
        self.size = size
        self.tier = tier
        self.cornerRadius = cornerRadius
        self.placeholderSystemImage = placeholderSystemImage
        _cachedImage = State(initialValue: initialImage)
    }

    private var resolvedTier: ArtworkTier {
        tier ?? ((size ?? 0) >= 480 ? .hero : .thumb)
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
        .task(id: id) {
            url = nil

            let t = resolvedTier

            // 1. Sync RAM hit in .task (not in body) — safe: reads in task closures are
            //    not tracked by @Observable, so this does NOT create an observation on the
            //    global cache dictionary.
            if let ram = artworkCache.cachedImage(for: id, tier: t) {
                cachedImage = ram
                return
            }

            // 2. Async load via artworkCache (disk → network → populates RAM).
            //    cachedImage is NOT cleared — init image stays visible while loading.
            if let image = await artworkCache.load(coverArtId: id, tier: t) {
                cachedImage = image
                return
            }

            // 3. Safety net: artworkCache failed — enter URL/AsyncImage path only if
            //    nothing is already showing.
            guard cachedImage == nil else { return }
            if let localURL = await container?.downloadService.localCoverArtURL(forId: id) {
                url = localURL
                return
            }
            url = await container?.libraryService.coverArtURL(id: id, size: size)
        }
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
