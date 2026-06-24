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
            PlaylistThemedBackground(
                coverArtId: coverArtId,
                coverImage: coverImage,
                theme: theme,
                heroHeight: heroHeight,
                lightMelt: contentBelow,
                meltEnabled: junctionColors.isEmpty
            )
            .frame(width: geo.size.width, height: heroHeight + stretch)
            .offset(y: -stretch)
            .id(coverRefreshID)
        }
        .frame(height: heroHeight)
    }

    /// A multi-colour gradient band — the cover's sampled bottom-edge colours (top) melting into the dominant
    /// body colour (bottom) — masked by a slow, organic LIQUID edge that interlocks with the cover's bottom so
    /// the artwork dissolves into the body in soft animated waves.
    @ViewBuilder
    private var junctionBand: some View {
        if junctionColors.count == 5 {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 1.1
                MeshGradient(
                    width: 5, height: 2,
                    points: [
                        SIMD2<Float>(0, 0), SIMD2<Float>(0.25, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(0.75, 0), SIMD2<Float>(1, 0),
                        SIMD2<Float>(0, 1), SIMD2<Float>(0.25, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(0.75, 1), SIMD2<Float>(1, 1),
                    ],
                    colors: junctionColors + Array(repeating: theme.dominantColor, count: 5)
                )
                .frame(height: 150)
                .mask(LiquidEdge(phase: phase, amplitude: 24))
            }
            .frame(height: 150)
            // Overlap the cover by the wave amplitude so the liquid crests lick up INTO the artwork's bottom.
            .padding(.top, -24)
        }
    }
}

/// A filled shape whose TOP edge is an organic liquid wave (a sum of sines), used to mask the junction band so
/// the cover's bottom and the colour mix interlock in soft animated crests.
private struct LiquidEdge: Shape {
    var phase: Double
    var amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = amplitude  // the wavy edge oscillates around y = amplitude (crests reach the very top)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: mid))
        let steps = 64
        for i in 0...steps {
            let frac = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + rect.width * frac
            let xx = Double(x)
            let y = mid
                + amplitude * 0.55 * CGFloat(sin(xx / 46 + phase))
                + amplitude * 0.30 * CGFloat(sin(xx / 27 - phase * 1.4))
                + amplitude * 0.15 * CGFloat(sin(xx / 15 + phase * 0.7))
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
