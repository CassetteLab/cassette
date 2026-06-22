// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI

/// Apple-Music-style "Move and Scale" square cropper for playlist cover photos: a dark screen, the photo
/// fills a square viewport, pan + pinch to position it (clamped so the image always covers the square — no
/// black gaps), then "Choose" renders exactly what's framed. Replaces UIImagePickerController's clunky
/// built-in crop. iOS-only.
struct SquareCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var viewport: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) - CassetteSpacing.xl * 2
                ZStack {
                    Color.black.ignoresSafeArea()
                    imageLayer(side)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous)
                                .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear { viewport = side }
                .onChange(of: side) { _, new in viewport = new }
            }
            .background(Color.black)
            .navigationTitle("Move and Scale")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }.tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") { performCrop() }.tint(.white).fontWeight(.semibold)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func imageLayer(_ side: CGFloat) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale * pinch)
                    .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            }
            .frame(width: side, height: side)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = clampedScale(scale * value)
                        offset = clampedOffset(offset, side: side)
                    }
                    .simultaneously(with:
                        DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset = clampedOffset(
                                    CGSize(width: offset.width + value.translation.width,
                                           height: offset.height + value.translation.height),
                                    side: side
                                )
                            }
                    )
            )
    }

    private func clampedScale(_ s: CGFloat) -> CGFloat { min(max(s, 1), 6) }

    /// Keep the (scaledToFill, scaled) image covering the square: cap the pan to the overflow on each axis.
    private func clampedOffset(_ o: CGSize, side: CGFloat) -> CGSize {
        let minDim = min(image.size.width, image.size.height)
        guard minDim > 0 else { return .zero }
        let fill = side / minDim
        let dispW = image.size.width * fill * scale
        let dispH = image.size.height * fill * scale
        let maxX = max(0, (dispW - side) / 2)
        let maxY = max(0, (dispH - side) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX),
                      height: min(max(o.height, -maxY), maxY))
    }

    @MainActor
    private func performCrop() {
        let side = viewport
        guard side > 0 else { onCancel(); return }
        let framed = Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(width: side, height: side)
            .clipped()
        let renderer = ImageRenderer(content: framed)
        renderer.scale = max(2, 1024 / side)   // ~1024px output
        if let ui = renderer.uiImage {
            onCrop(ui)
        } else {
            onCancel()
        }
    }
}
#endif
