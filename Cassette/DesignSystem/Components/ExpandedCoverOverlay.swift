// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The artwork full-frame, growing out of the cover it was tapped on.
///
/// Presented with the zoom transition the app already uses for grid-to-detail
/// (`cassetteZoomTransition`), so the cover a person tapped is the cover that grows: one object
/// moving, not two states cross-fading. The system owns the animation and the interactive
/// drag-to-dismiss that comes with it, which is why there is no hand-rolled dismissal here.
///
/// Themed with the screen's own dominant colour and content colour, `cassetteCoverStyle` on the
/// artwork, and a back control that is a real toolbar item — so it lands under the status bar with the system's own
/// glass treatment, where every other back button in the app sits.
struct ExpandedCoverOverlay: View {
    let coverArtId: String
    let title: String
    /// The screen's themed colour. The overlay never invents its own background.
    let backgroundColor: Color
    /// The screen's own content colour — black or white, decided from the theme's luminance. Taken
    /// from the detail screen rather than re-derived, so the chevron is the same colour as the one
    /// it replaces for the time the cover is open.
    let contentColor: Color
    /// What the screen already has, shown until the 1200 px tier arrives — never instead of it.
    let initialImage: PlatformImage?
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    private static let maxScale: CGFloat = 6

    var body: some View {
        #if os(iOS)
        // A NavigationStack, so the back control is a real toolbar item: the system gives it its
        // glass treatment, its tap target and its place under the status bar. Hand-placing it in
        // the ZStack put a bare chevron on top of the clock.
        NavigationStack {
            artwork
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.cassetteCellTitle)
                        }
                        .tint(contentColor)
                        .accessibilityLabel("Back")
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        #else
        artwork
            .overlay(alignment: .topLeading) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(contentColor)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(CassetteSpacing.l)
            }
            .frame(minWidth: 600, minHeight: 600)
        #endif
    }

    private var artwork: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            cover
        }
    }

    /// Explicitly sized rather than left to the layout: "as large as the screen allows" is the
    /// whole point, and a fitted image in a ZStack had been settling for about two thirds of it.
    private var cover: some View {
        GeometryReader { geo in
            let side = max(0, min(geo.size.width, geo.size.height) - CassetteSpacing.l * 2)
            CoverArtView(
                id: coverArtId,
                size: ArtworkTier.hero.decodePixels,
                tier: .hero,
                initialImage: initialImage
            )
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
            // Not `cassetteCoverStyle`: its edge follows the colour scheme (a shadow in light mode,
            // an 8% white hairline in dark mode), and here the backdrop is the cover's own dominant
            // colour, so in dark mode the artwork melted into it. The edge follows the backdrop
            // instead, in every scheme: `contentColor` is already black on a light theme and white
            // on a dark one, and the shadow lifts the cover off a backdrop of its own colour.
            .overlay {
                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                    .strokeBorder(contentColor.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .scaleEffect(scale * pinch)
            // Panning belongs to the zoomed cover only; unzoomed, a drag is the system's dismissal.
            .offset(
                x: offset.width + (scale > 1 ? dragTranslation.width : 0),
                y: offset.height + (scale > 1 ? dragTranslation.height : 0)
            )
            .gesture(zoomAndPan)
            .onTapGesture(count: 2) { toggleZoom() }
            .accessibilityLabel(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The shape `SquareCropView` already uses: pinch and drag together, clamped on release.
    private var zoomAndPan: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                scale = min(max(scale * value, 1), Self.maxScale)
                if scale == 1 { offset = .zero }
            }
            .simultaneously(with:
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        // Unzoomed, the drag was the system's interactive dismissal, not a pan.
                        guard scale > 1 else {
                            offset = .zero
                            return
                        }
                        offset = CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        )
                    }
            )
    }

    private func toggleZoom() {
        withAnimation(.smooth(duration: 0.25)) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = 2.5
            }
        }
    }
}
