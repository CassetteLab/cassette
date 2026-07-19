// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Palette per mood. Chosen for legibility of white text on the darker end of each pair rather
/// than for literal colour symbolism.
private func moodColors(_ mood: Mood) -> [Color] {
    switch mood {
    case .night:     return [Color(red: 0.11, green: 0.13, blue: 0.35), Color(red: 0.35, green: 0.22, blue: 0.55)]
    case .energetic: return [Color(red: 0.85, green: 0.28, blue: 0.14), Color(red: 0.95, green: 0.60, blue: 0.10)]
    case .workout:   return [Color(red: 0.70, green: 0.10, blue: 0.28), Color(red: 0.90, green: 0.30, blue: 0.35)]
    case .chill:     return [Color(red: 0.10, green: 0.42, blue: 0.40), Color(red: 0.30, green: 0.65, blue: 0.55)]
    case .focus:     return [Color(red: 0.18, green: 0.28, blue: 0.45), Color(red: 0.35, green: 0.48, blue: 0.62)]
    }
}

/// One mood tile in Discover. Opens the server playlist backing the mood.
///
/// Rendered only once the mood has been synced at least once — a card that navigates to a playlist
/// that does not exist yet would be a dead end, so DiscoverView filters on `playlistId` before
/// building these.
struct MoodCard: View {
    let mood: Mood
    let playlistId: String

    var body: some View {
        NavigationLink {
            PlaylistDetailView(playlistId: playlistId, name: String(localized: mood.title), coverArtId: nil)
        } label: {
            LinearGradient(colors: moodColors(mood), startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 140, height: 160)
                .overlay(alignment: .topLeading) {
                    Image(systemName: mood.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(CassetteSpacing.m)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(String(localized: mood.title))
                        .font(.cassetteCellTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(CassetteSpacing.m)
                }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: mood.title))
    }
}
