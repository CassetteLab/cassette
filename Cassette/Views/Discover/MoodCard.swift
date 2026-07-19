// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// One mood tile in Discover, presented like every other playlist in the app: the real server cover
/// on top, the name underneath. The cover is the gradient generated for the playlist, so a mood
/// looks the same here, in the playlists list, and in any other Subsonic client.
///
/// Rendered only once the mood has been synced at least once — DiscoverView filters on `playlistId`
/// first, so this never navigates to a playlist that does not exist yet.
struct MoodCard: View {
    let mood: Mood
    let playlistId: String

    private let cardSize: CGFloat = 140

    var body: some View {
        NavigationLink {
            PlaylistDetailView(playlistId: playlistId, name: String(localized: mood.title), coverArtId: playlistId)
        } label: {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                CoverArtCard(id: playlistId, size: cardSize, placeholderSystemImage: mood.symbolName)
                Text(String(localized: mood.title))
                    .font(.cassetteCaption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: cardSize, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: mood.title))
    }
}
