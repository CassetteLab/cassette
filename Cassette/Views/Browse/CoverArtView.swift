// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Async cover art loader. Resolves via ArtworkImageCache (RAM → disk → network).
/// Falls back to the URL/AsyncImage path only if ArtworkImageCache fails entirely.
/// Use `CoverArtCard` in views — it wraps this with clip, shadow, and border handling.
struct CoverArtView: View {
    let id: String
    let size: Int?
    var cornerRadius: CGFloat = 0
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil

    @Environment(ArtworkImageCache.self) private var artworkCache

    var body: some View {
        // Sync RAM lookup happens in body where @Environment is available.
        // Caller-supplied initialImage takes precedence; RAM cache fills the gap.
        // The result is passed as initialValue so CoverArtViewContent's @State
        // is non-nil on frame 0 when the cache is warm.
        CoverArtViewContent(
            id: id,
            size: size,
            cornerRadius: cornerRadius,
            placeholderSystemImage: placeholderSystemImage,
            initialImage: initialImage ?? artworkCache.cachedImage(for: id)
        )
    }
}

// MARK: - Content

private struct CoverArtViewContent: View {
    let id: String
    let size: Int?
    let cornerRadius: CGFloat
    let placeholderSystemImage: String

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkCache
    @State private var cachedImage: PlatformImage?
    @State private var url: URL?

    init(id: String, size: Int?, cornerRadius: CGFloat, placeholderSystemImage: String, initialImage: PlatformImage?) {
        self.id = id
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholderSystemImage = placeholderSystemImage
        _cachedImage = State(initialValue: initialImage)
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

            // 1. Sync RAM hit — refreshes cachedImage on id changes without clearing first.
            if let ram = artworkCache.cachedImage(for: id) {
                cachedImage = ram
                return
            }

            // 2. Async load via artworkCache (disk → network → populates RAM).
            //    cachedImage is NOT cleared — init image stays visible while loading.
            if let image = await artworkCache.load(coverArtId: id) {
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
