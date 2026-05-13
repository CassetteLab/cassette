// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Generates themed playlist cover art for each ``ThemePlaylistType``.
///
/// Uses `ImageRenderer` (MainActor-isolated) to render a 600×600 pt image with
/// a diagonal linear gradient, a centred SF symbol, and the playlist display
/// name in the bottom-left corner.
///
/// The struct carries no mutable state — one instance per call is typical.
/// Local file paths are available via the `nonisolated` static helpers so they
/// can be accessed from any concurrency context without a MainActor hop.
struct ThemePlaylistArtworkGenerator {

    // MARK: - Path utilities (nonisolated — callable from any concurrency context)

    /// The URL where the generated cover for `type` is (or will be) stored on disk.
    ///
    /// Path: `<Documents>/playlist-covers/<type.rawValue>.png`
    nonisolated static func localCoverURL(for type: ThemePlaylistType) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlist-covers/\(type.rawValue).png")
    }

    // MARK: - Generation

    /// Renders the themed artwork for `type` and returns a platform image.
    @MainActor
    func generateArtwork(for type: ThemePlaylistType) -> PlatformImage {
        let renderer = ImageRenderer(content: ArtworkRenderView(type: type))
        renderer.proposedSize = .init(width: 600, height: 600)
        renderer.scale = 1
        #if canImport(UIKit)
        return renderer.uiImage ?? PlatformImage()
        #elseif canImport(AppKit)
        return renderer.nsImage ?? PlatformImage(size: NSSize(width: 600, height: 600))
        #endif
    }

    /// Renders the themed artwork and returns its PNG-encoded bytes.
    @MainActor
    func pngData(for type: ThemePlaylistType) -> Data? {
        let image = generateArtwork(for: type)
        #if canImport(UIKit)
        return image.pngData()
        #elseif canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}

// MARK: - Render view

private struct ArtworkRenderView: View {
    let type: ThemePlaylistType

    var body: some View {
        ZStack {
            LinearGradient(
                colors: type.artworkGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: type.artworkSymbol)
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.3))

            VStack {
                Spacer()
                HStack {
                    Text(type.displayName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(24)
            }
        }
        .frame(width: 600, height: 600)
    }
}

// MARK: - Artwork palette & symbols (presentation layer — not part of domain model)

private extension ThemePlaylistType {
    var artworkGradientColors: [Color] {
        switch self {
        case .mostPlayedMonth:    [Color(hex: "#6C47F5"), Color(hex: "#C060F0")]
        case .hiddenGems:         [Color(hex: "#0EA5E9"), Color(hex: "#10B981")]
        case .forgottenFavorites: [Color(hex: "#F59E0B"), Color(hex: "#EF4444")]
        case .recentDiscoveries:  [Color(hex: "#3B82F6"), Color(hex: "#06B6D4")]
        }
    }

    var artworkSymbol: String {
        switch self {
        case .mostPlayedMonth:    "chart.bar.fill"
        case .hiddenGems:         "sparkle"
        case .forgottenFavorites: "clock.arrow.circlepath"
        case .recentDiscoveries:  "antenna.radiowaves.left.and.right"
        }
    }
}
