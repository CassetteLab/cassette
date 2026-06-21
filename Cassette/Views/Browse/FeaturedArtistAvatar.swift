// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// The round avatar for a "Featured Artist" cell. Shows the album cover (which we already have from the
/// track) immediately, then swaps to the real ARTIST PHOTO once it's resolved and confirmed loadable —
/// progressively, with no placeholder flash (CoverArtView keeps the prior image until the new one resolves,
/// and we pre-load the photo so the swap is a RAM hit).
///
/// Resolution is **Path A, zero per-artist fetch**: the artist's cover-art id comes from the shared
/// `LibraryService` artist-name index (`findArtist(byName:)`, built once from `getArtists`), then the bytes
/// load through the existing `artworkImageCache`. If the artist isn't found (offline / name mismatch / id
/// collision) or has no photo, the album cover stays — never a placeholder. Cross-platform.
struct FeaturedArtistAvatar: View {
    let artist: FeaturedArtist
    var size: CGFloat = 76

    @Environment(\.appContainer) private var container
    @State private var resolvedArtistCoverArt: String?

    private var albumCoverId: String { artist.coverArtId ?? artist.id }

    var body: some View {
        CoverArtView(
            id: resolvedArtistCoverArt ?? albumCoverId,
            size: 160,
            placeholderSystemImage: "music.mic"
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: artist.id) {
            await resolveArtistPhoto()
        }
    }

    private func resolveArtistPhoto() async {
        guard resolvedArtistCoverArt == nil, let container else { return }
        // Name → ArtistID3 via the shared, build-once index; verify the id to be collision-safe.
        guard let match = await container.libraryService.findArtist(byName: artist.name),
              match.id == artist.id,
              let coverArt = match.coverArt,
              coverArt != albumCoverId else { return }
        // Only swap once the photo actually loads — so a photoless artist keeps the album cover, no flash.
        guard await container.artworkImageCache.load(coverArtId: coverArt, tier: .thumb) != nil else { return }
        resolvedArtistCoverArt = coverArt
    }
}
