// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftUI

/// Async cover art loader. Resolves the URL via LibraryService, then hands it to AsyncImage.
/// Use `CoverArtCard` in views — it wraps this with clip, shadow, and border handling.
struct CoverArtView: View {
    let id: String
    let size: Int?
    var cornerRadius: CGFloat = 0
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil

    @Environment(\.appContainer) private var container
    @State private var url: URL?
    @State private var asyncImageLoaded = false

    var body: some View {
        ZStack {
            // Async path always resolves; onAppear dismisses the initial image overlay.
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.15)) {
                                asyncImageLoaded = true
                            }
                        }
                case .failure:
                    placeholder
                case .empty:
                    if initialImage == nil {
                        GeometryReader { geo in
                            SkeletonBlock(
                                width: geo.size.width,
                                height: geo.size.height,
                                cornerRadius: cornerRadius
                            )
                        }
                    }
                @unknown default:
                    EmptyView()
                }
            }

            // Initial image covers the async placeholder until the network image arrives.
            if let initialImage, !asyncImageLoaded {
                Image(platformImage: initialImage)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: id) {
            asyncImageLoaded = false
            Logger.ui.debug("[DBG] CoverArtView.task id='\(id, privacy: .public)'")
            // Local file first — avoids redundant network requests and works offline.
            if let localURL = await container?.downloadService.localCoverArtURL(forId: id) {
                Logger.ui.debug("[DBG] CoverArtView.task local hit url='\(localURL.absoluteString, privacy: .public)'")
                url = localURL
                return
            }
            // Fall back to server URL (nil if offline or no server configured).
            Logger.ui.debug("[DBG] CoverArtView.task no local file — falling back to server for id='\(id, privacy: .public)'")
            url = await container?.libraryService.coverArtURL(id: id, size: size)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [CassetteColors.accent.opacity(0.25), CassetteColors.accent.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: placeholderSystemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
