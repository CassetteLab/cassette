// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct WrappedClosingSlide: View {
    let year: Int
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    @State private var renderedImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var isRendering = false
    #endif

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: CassetteSpacing.m) {
                    Image(systemName: "waveform")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(.white)

                    Text("Thanks for\nlistening.")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .kerning(-1)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Your \(year) Wrapped")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer(minLength: CassetteSpacing.xl)

                HStack(spacing: CassetteSpacing.m) {
                    statCard(value: data.totalSecondsListened.wrappedCompactLabel(), label: "listened")
                    statCard(value: "\(data.totalTracksPlayed)", label: data.totalTracksPlayed == 1 ? "play" : "plays")
                    statCard(value: "\(data.totalUniqueArtists)", label: data.totalUniqueArtists == 1 ? "artist" : "artists")
                }
                .padding(.horizontal, CassetteSpacing.xl)

                Spacer(minLength: CassetteSpacing.l)

                #if os(iOS)
                shareButton
                    .padding(.horizontal, CassetteSpacing.xl)
                #endif

                Spacer()
            }
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            if let image = renderedImage {
                ShareSheet(items: [image])
            }
        }
        #endif
    }

    // MARK: - Stat card

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: CassetteSpacing.xs) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .kerning(-0.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CassetteSpacing.m)
        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
    }

    // MARK: - Share (iOS only)

    #if os(iOS)
    private var shareButton: some View {
        Button {
            Task { await renderAndShare() }
        } label: {
            HStack(spacing: CassetteSpacing.s) {
                if isRendering {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isRendering ? "Preparing…" : "Share your Wrapped")
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CassetteSpacing.m)
            .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRendering)
    }

    @MainActor
    private func renderAndShare() async {
        isRendering = true
        let card = WrappedShareCardView(year: year, data: data, palette: palette)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0  // 360×640 pt × @3x = 1080×1920 px
        renderedImage = renderer.uiImage
        isRendering = false
        if renderedImage != nil { showShareSheet = true }
    }
    #endif
}

// MARK: - UIActivityViewController wrapper

#if os(iOS)
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
