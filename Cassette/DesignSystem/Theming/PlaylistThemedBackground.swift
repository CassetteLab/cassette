// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Apple-Music-style blended background for playlist surfaces: the cover bleeds from the top, blurred,
/// and fades into the theme color so the artwork "melts" into the page. Cross-platform — the only `#if os`
/// is the system-background color bridge (not a feature gate), so Phase 5 macOS reuses it as-is.
///
/// The cover SOURCE is pluggable via `coverArtId` / `coverImage`; Phase 2 can feed a rendered gradient's
/// image here instead. When the theme hasn't resolved yet (`.unthemed`) it falls back to the system
/// background with no blend, so it degrades cleanly before the dominant color is known.
struct PlaylistThemedBackground: View {
    let coverArtId: String?
    let coverImage: PlatformImage?
    let theme: PlaylistTheme

    var body: some View {
        ZStack {
            (theme.isThemed ? theme.dominantColor : systemBackground)

            if theme.isThemed, let coverArtId {
                // Blurred cover bleeding from the top, masked to fade into the solid theme color below.
                CoverArtView(id: coverArtId, size: 600, initialImage: coverImage)
                    .frame(height: 460)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: 60)
                    .opacity(0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.30),
                                .init(color: .clear, location: 0.85),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        // Cross-fade the whole blend when the theme color changes (cover load / track change).
        .animation(.easeInOut(duration: 0.35), value: theme)
        .ignoresSafeArea()
    }

    private var systemBackground: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}
