// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Async cover art view. Resolves the URL via LibraryService (cached client),
/// then hands it to AsyncImage. Shows a placeholder while loading or on error.
struct CoverArtView: View {
    let id: String
    let size: Int?

    @Environment(\.appContainer) private var container
    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .task(id: id) {
            url = await container?.libraryService.coverArtURL(id: id, size: size)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}
