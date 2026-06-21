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
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                // Stretchy header: on over-scroll at the top, grow the cover UPWARD to fill the bounce
                // instead of revealing the solid page color behind it.
                let stretch = max(0, geo.frame(in: .global).minY)
                PlaylistThemedBackground(
                    coverArtId: coverArtId,
                    coverImage: coverImage,
                    theme: theme,
                    heroHeight: heroHeight
                )
                .frame(width: geo.size.width, height: heroHeight + stretch)
                .offset(y: -stretch)
                .id(coverRefreshID)
            }
            .frame(height: heroHeight)

            // Floating content over the cover's lower part. Non-interactive cover behind it stays out of the
            // way of taps (artist links, transport buttons).
            content()
                .padding(.bottom, CassetteSpacing.l)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
    }
}
