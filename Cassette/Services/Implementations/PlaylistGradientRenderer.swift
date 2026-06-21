// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Renders a `PlaylistGradientSpec` to a square JPEG to become a real playlist cover. Mirrors the proven
/// `WrappedCoverRenderer` path: `ImageRenderer` (cross-platform) + a platform JPEG-encode bridge (the only
/// `#if os`). Built cross-platform from day one so the Phase 5 macOS pass is wiring, not a rewrite.
@MainActor
enum PlaylistGradientRenderer {
    static func jpegData(for spec: PlaylistGradientSpec, side: CGFloat = 1024, compression: Double = 0.85) -> Data? {
        let view = PlaylistGradientView(spec: spec).frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0

        #if os(iOS)
        return renderer.uiImage?.jpegData(compressionQuality: compression)
        #elseif os(macOS)
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
        #else
        return nil
        #endif
    }
}
