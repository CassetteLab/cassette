// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Apple-Music-style immersive background for the playlist detail view: the cover fills the top
/// **full-bleed** (edge-to-edge, under the nav bar via `.ignoresSafeArea`), a **blurred melt** fades it into
/// the themed body color around the start of the track list, and below that it's solid body color. The
/// detail content (title / by / transport) floats over the lower part of the cover.
///
/// Cover-agnostic — the same path renders a gradient JPEG, an uploaded photo, or a server album cover. The
/// blurred melt is flattened into one Metal-backed bitmap via `.drawingGroup()` (the FullPlayer pattern), so
/// the blur is rasterized once per cover change, never recomputed per frame. The only `#if os` is the
/// system-background bridge. Static fade (no scroll-driven parallax — that's a post-rebrand polish).
struct PlaylistThemedBackground: View {
    let coverArtId: String?
    let coverImage: PlatformImage?
    let theme: PlaylistTheme
    /// Height of the full-bleed cover region (from the screen top), beyond which it's solid body color.
    var heroHeight: CGFloat = 460
    /// When set (a user-picked gradient playlist), the hero renders the gradient CRISP from the spec instead
    /// of the uploaded JPEG. The JPEG stays the cards/cross-device source of truth; this is a local crisp
    /// enrichment. Default nil keeps every other caller (photo / server cover / ImmersiveCoverHero) unchanged.
    var gradientSpec: PlaylistGradientSpec? = nil
    /// Fade ONLY the bottom edge (square covers shown in full with content sitting below) instead of the lower
    /// ~half (full-bleed covers with content floating over them).
    var lightMelt: Bool = false

    private var bodyColor: Color { theme.isThemed ? theme.dominantColor : systemBackground }

    var body: some View {
        ZStack(alignment: .top) {
            bodyColor

            if theme.isThemed, let coverArtId {
                ZStack(alignment: .top) {
                    // Sharp full-bleed cover — an ANIMATED mesh gradient from the spec (foreground only, cheap;
                    // the melt below stays static), else the artwork. Edge-to-edge.
                    Group {
                        if let gradientSpec {
                            AnimatedGradientHeroView(spec: gradientSpec)
                        } else {
                            CoverArtView(id: coverArtId, size: 1000, initialImage: coverImage)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .clipped()

                    // Light blurred melt: the cover softly fades into the (now bottom-matched) body color toward
                    // the bottom — a slight transition that gives the floating title/buttons a legible backdrop.
                    blurredMelt(coverArtId: coverArtId)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// The lower part of the hero: a blurred copy of the cover dissolving into the solid body color, masked
    /// so the top of the hero keeps the sharp cover. Rasterized once via `.drawingGroup()`.
    @ViewBuilder
    private func blurredMelt(coverArtId: String) -> some View {
        ZStack {
            Group {
                if let gradientSpec {
                    PlaylistGradientView(spec: gradientSpec)
                } else {
                    CoverArtView(id: coverArtId, size: 600, initialImage: coverImage)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipped()
            // Strong blur for the light melt: a concentrated, heavily-diffused bottom band reads better across
            // detailed covers than a long, washed gradient.
            .blur(radius: lightMelt ? 34 : 16)

            // Resolve to the dominant body color EARLY so the transition reads as a colour continuity (the
            // cover melting into the dominant tint) rather than a washed-out blurred-cover band.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: lightMelt ? 0.86 : 0.30),
                    .init(color: bodyColor, location: lightMelt ? 1.0 : 0.80),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)
        }
        .frame(height: heroHeight)
        // Only the lower portion melts; the top keeps the sharp cover visible.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: lightMelt ? 0.88 : 0.32),
                    .init(color: .black, location: lightMelt ? 1.0 : 0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .drawingGroup()
    }

    private var systemBackground: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}
