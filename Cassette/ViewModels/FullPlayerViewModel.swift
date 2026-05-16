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
        guard let url,
              let (data, _) = try? await session.data(from: url),
              let image = PlatformImage(data: data) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        withAnimation(.easeInOut(duration: 0.4)) {
            coverImage = image
            dominantColor = color
            isLightBackground = color.luminance > 0.6
        }
    }
}
