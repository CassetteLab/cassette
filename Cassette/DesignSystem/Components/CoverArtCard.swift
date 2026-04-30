// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Unified cover art wrapper used everywhere an album or playlist thumbnail appears.
///
/// Handles:
/// - Async loading via CoverArtView
/// - Consistent 1:1 aspect ratio and clip
/// - Shadow in light mode / thin border in dark mode via `.cassetteCoverStyle()`
/// - Accessible placeholder (gradient + music note icon)
///
/// Usage:
/// ```swift
/// CoverArtCard(id: album.coverArt ?? album.id, size: 60)
/// CoverArtCard(id: song.coverArt ?? song.id, size: 220, cornerRadius: CassetteCornerRadius.large)
/// ```
struct CoverArtCard: View {
    let id: String
    let size: CGFloat
    var cornerRadius: CGFloat = CassetteCornerRadius.standard
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil

    var body: some View {
        CoverArtView(id: id, size: Int(size * 2), placeholderSystemImage: placeholderSystemImage, initialImage: initialImage)  // 2× for @2x sharpness
            .frame(width: size, height: size)
            .cassetteCoverStyle(cornerRadius: cornerRadius)
    }
}

#Preview("Light") {
    HStack(spacing: CassetteSpacing.l) {
        CoverArtCard(id: "preview-small", size: 44)
        CoverArtCard(id: "preview-medium", size: 60)
        CoverArtCard(id: "preview-large", size: 160, cornerRadius: CassetteCornerRadius.large)
    }
    .padding()
}

#Preview("Dark") {
    HStack(spacing: CassetteSpacing.l) {
        CoverArtCard(id: "preview-small", size: 44)
        CoverArtCard(id: "preview-medium", size: 60)
        CoverArtCard(id: "preview-large", size: 160, cornerRadius: CassetteCornerRadius.large)
    }
    .padding()
    .preferredColorScheme(.dark)
}
