// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedYearlyCard: View {
    let playlist: WrappedYearlyPlaylist

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationLink {
            PlaylistDetailView(playlistId: playlist.id, name: playlist.name, coverArtId: playlist.coverArtId)
        } label: {
            MeshGradientBackground(palette: WrappedYearPalette.colors(for: playlist.year), animated: !reduceMotion)
                .frame(width: 140, height: 160)
                .overlay { cardOverlay }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            Text(String(playlist.year))
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("Wrapped")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CassetteSpacing.s)
    }
}
