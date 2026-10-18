// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The Apple-Music-style immersive cover hero, shared across detail surfaces (playlist, album, …). It is the
/// FIRST item of a scroll container so it scrolls up with the content. The cover fills full-bleed, blurs and
/// melts into the themed body color (`PlaylistThemedBackground`), stretches upward on over-scroll, and the
/// caller's `content` (title / artist / transport …) floats over the cover's lower part.
///
/// Pair it with: a solid `bodyColor` page `.background(...)`, `.ignoresSafeArea(.container, edges: .top)` on
/// the scroll container (so the cover reaches the screen top), and a transparent nav bar.
struct ImmersiveCoverHero<Content: View>: View {
    let coverArtId: String?
    let coverImage: PlatformImage?
    let theme: PlaylistTheme
    let heroHeight: CGFloat
    /// Re-mount key so the cover reloads when it changes (e.g. an edit upload). Defaults to a constant.
    var coverRefreshID: AnyHashable = 0
    /// Square album/playlist covers put metadata below on narrow windows and beside the cover on wide ones.
    /// Otherwise the content floats over the full-bleed cover, as it does for artist photos.
    var contentBelow: Bool = false
    var gradientSpec: PlaylistGradientSpec? = nil
    /// Takes the cover full-frame in the screen it already lives in. Attached to the cover alone,
    /// not the whole hero: the content below (or over) it owns its taps — transport, artist links.
    var onCoverTap: (() -> Void)? = nil
    /// Marks the cover as the source of the zoom transition to the full-frame artwork, so the
    /// thing that grows is the thing that was tapped.
    var zoomSourceID: String? = nil
    var zoomNamespace: Namespace.ID? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// nil until the first measurement. Starting at `false` would render one frame in the narrow
    /// layout on iPad and then snap, which reads as a flicker when opening an album.
    @State private var measuredWideLayout: Bool?

    /// The size class is the best guess available before the view has a width; the measurement
    /// replaces it as soon as there is one, because a regular-width window can still be narrow
    /// in Split View.
    private var usesWideLayout: Bool {
        measuredWideLayout ?? (contentBelow && horizontalSizeClass == .regular)
    }

    private var coverHeight: CGFloat {
        usesWideLayout ? CassetteLayout.detailCoverSize : heroHeight
    }

    var body: some View {
        Group {
            if contentBelow && usesWideLayout {
                HStack(spacing: CassetteSpacing.xxxl) {
                    coverHero
                        .frame(width: CassetteLayout.detailCoverSize)
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                    content()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, CassetteSpacing.xxxl)
                .padding(.top, CassetteSpacing.xxxxl)
                .padding(.bottom, CassetteSpacing.xxl)
            } else if contentBelow {
                VStack(spacing: 0) {
                    coverHero
                    content()
                        .padding(.top, CassetteSpacing.m)
                        .padding(.bottom, CassetteSpacing.xl)
                }
                .frame(maxWidth: .infinity)
            } else {
                ZStack(alignment: .bottom) {
                    coverHero
                    // Floating content over the cover's lower part. Non-interactive cover behind it stays out of
                    // the way of taps (artist links, transport buttons).
                    content()
                        .padding(.bottom, CassetteSpacing.l)
                }
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: Bool.self) { geometry in
            contentBelow && geometry.size.width >= CassetteLayout.wideDetailMinimum
        } action: { measuredWideLayout = $0 }
    }

    private var coverHero: some View {
        GeometryReader { geo in
            // Stretchy header: on over-scroll at the top, grow the cover UPWARD to fill the bounce instead of
            // revealing the solid page color behind it.
            let stretch = usesWideLayout ? 0 : max(0, geo.frame(in: .global).minY)
            PlaylistThemedBackground(
                coverArtId: coverArtId,
                coverImage: coverImage,
                theme: theme,
                heroHeight: coverHeight,
                gradientSpec: gradientSpec,
                lightMelt: contentBelow
            )
            .frame(width: geo.size.width, height: coverHeight + stretch)
            .offset(y: -stretch)
            .id(coverRefreshID)
        }
        .frame(height: coverHeight)
        .cassetteMatchedTransitionSource(id: zoomSourceID, in: zoomNamespace)
        .contentShape(Rectangle())
        .onTapGesture { onCoverTap?() }
    }
}
