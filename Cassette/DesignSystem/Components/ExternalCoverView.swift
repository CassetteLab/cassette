// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Drop-in replacement for `AsyncImage` that routes external cover URLs through
/// `ExternalArtworkCache` (memory → disk → network) instead of hitting the network
/// on every render. Use inside a fixed-size container; the image fills its parent.
struct ExternalCoverView<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.appContainer) private var container
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await container?.externalArtworkCache.image(for: url)
        }
    }
}
