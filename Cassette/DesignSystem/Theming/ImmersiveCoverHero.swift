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
    /// When true the cover keeps its square ratio and the content sits BELOW it (album/playlist covers shown in
    /// full); when false (default) the content floats over the full-bleed cover (artist photos).
    var contentBelow: Bool = false
    /// When set (5 colours sampled from the cover's bottom edge), a multi-colour gradient band is laid between
    /// the cover and the content (the mix at top → the dominant body colour), and the cover's bottom melt is
    /// dropped so its sharp edge meets the matching mix. Empty keeps the plain behaviour.
    var junctionColors: [Color] = []
    @ViewBuilder let content: () -> Content

    var body: some View {
        if contentBelow {
            VStack(spacing: 0) {
                coverHero
                junctionBand
                content()
                    .padding(.top, junctionColors.isEmpty ? CassetteSpacing.m : CassetteSpacing.s)
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

    private var coverHero: some View {
        GeometryReader { geo in
            // Stretchy header: on over-scroll at the top, grow the cover UPWARD to fill the bounce instead of
            // revealing the solid page color behind it.
            let stretch = max(0, geo.frame(in: .global).minY)
            coverBackground(width: geo.size.width, stretch: stretch)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private func coverBackground(width: CGFloat, stretch: CGFloat) -> some View {
        let bg = PlaylistThemedBackground(
            coverArtId: coverArtId,
            coverImage: coverImage,
            theme: theme,
            heroHeight: heroHeight,
            lightMelt: contentBelow,
            meltEnabled: junctionColors.isEmpty
        )
        .frame(width: width, height: heroHeight + stretch)
        .offset(y: -stretch)
        .id(coverRefreshID)

        if junctionColors.isEmpty {
            bg
        } else {
            // Metal liquid: ripple the cover's BOTTOM edge with the `liquidBottom` distortion shader so the
            // artwork flows into the matching junction mix below in slow, organic, animated waves.
            TimelineView(.animation) { timeline in
                let time = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 628.318))
                bg.distortionEffect(
                    ShaderLibrary.liquidBottom(.boundingRect, .float(time), .float(26), .float(150)),
                    maxSampleOffset: CGSize(width: 32, height: 32)
                )
            }
        }
    }

    /// The multi-colour junction: the cover's sampled bottom-edge colours (top) melting into the dominant body
    /// colour (bottom). The LIQUID motion is the Metal ripple on the cover above; this band just carries the
    /// matching colour mix down into the flat body.
    @ViewBuilder
    private var junctionBand: some View {
        if junctionColors.count == 5 {
            MeshGradient(
                width: 5, height: 2,
                points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(0.25, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(0.75, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.25, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(0.75, 1), SIMD2<Float>(1, 1),
                ],
                colors: junctionColors + Array(repeating: theme.dominantColor, count: 5)
            )
            .frame(height: 120)
        }
    }
}
