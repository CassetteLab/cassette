// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Async cover art loader. Resolves the URL via LibraryService, then hands it to AsyncImage.
/// Use `CoverArtCard` in views — it wraps this with clip, shadow, and border handling.
struct CoverArtView: View {
    let id: String
    let size: Int?
    var placeholderSystemImage: String = "music.note"

    @Environment(\.appContainer) private var container
    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure, .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .task(id: id) {
            // Local file first — avoids redundant network requests and works offline.
            if let localURL = await container?.downloadService.localCoverArtURL(forId: id) {
                url = localURL
                return
            }
            // Fall back to server URL (nil if offline or no server configured).
            url = await container?.libraryService.coverArtURL(id: id, size: size)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.cassetteAccentSecondary.opacity(0.3), Color.cassetteAccent.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: placeholderSystemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
