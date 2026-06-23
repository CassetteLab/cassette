// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

@Observable
@MainActor
final class FullPlayerViewModel {
    var coverImage: PlatformImage? = nil
    var dominantColor: Color = .black
    /// Average colour of the cover's TOP strip — fills the gap ABOVE the fitted square cover in the player.
    var topColor: Color = .black
    /// Per-segment average colours of the cover's BOTTOM edge — feed the mesh that merges the cover into the body.
    var bottomColors: [Color] = []
    var isLightBackground: Bool = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    var contentColor: Color { isLightBackground ? .black : .white }
    var secondaryContentColor: Color { isLightBackground ? Color.black.opacity(0.7) : Color.white.opacity(0.7) }
    var tertiaryContentColor: Color { isLightBackground ? Color.black.opacity(0.5) : Color.white.opacity(0.5) }
    var glassTint: Color { isLightBackground ? Color.black.opacity(0.1) : Color.white.opacity(0.15) }

    func updateColors(for coverArtId: String?, colorExtractor: DominantColorExtractor, container: AppContainer?) async {
        guard let coverArtId else {
            withAnimation(.easeInOut(duration: 0.4)) {
                coverImage = nil
                dominantColor = .black
                topColor = .black
                bottomColors = []
                isLightBackground = false
            }
            return
        }
        let url: URL?
        if let localURL = await container?.downloadService.localCoverArtURL(forId: coverArtId) {
            url = localURL
        } else {
            url = await container?.libraryService.coverArtURL(id: coverArtId, size: 300)
        }
        guard let url, let (data, _) = try? await session.data(from: url) else { return }
        // Skip re-extraction if the color is already memoized (the image is still decoded for coverImage).
        let cachedColor = colorExtractor.cachedColor(for: coverArtId)
        // Decode + average OFF the main actor so a track change does not hitch the UI on the main thread.
        let processed: (image: PlatformImage, packed: Int?, topPacked: Int?, edge: [Int])? = await Task.detached(priority: .userInitiated) {
            guard let image = PlatformImage(data: data) else { return nil }
            let packed = cachedColor == nil ? DominantColorExtractor.packedAverageColor(from: image) : nil
            let topPacked = DominantColorExtractor.packedAverageColor(from: image, fromTop: true)
            let edge = DominantColorExtractor.bottomEdgeColors(from: image, count: 3)
            return (image, packed, topPacked, edge)
        }.value
        guard let processed else { return }
        let color = cachedColor ?? colorExtractor.storeColor(packed: processed.packed, for: coverArtId)
        let top = processed.topPacked.map { DominantColorExtractor.unpack($0) } ?? color
        let edge = processed.edge.map { DominantColorExtractor.unpack($0) }
        withAnimation(.easeInOut(duration: 0.4)) {
            coverImage = processed.image
            dominantColor = color
            topColor = top
            bottomColors = edge.isEmpty ? [color, color, color] : edge
            isLightBackground = color.luminance > 0.6
        }
    }
}
