// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Persistent mini-player bar anchored above the tab bar.
/// Visible only when a track is loaded in PlayerState.
/// Full implementation in Étape 4 (PlayerService wiring).
struct MiniPlayerView: View {
    // TODO(Étape 4): replace with real playback controls wired to PlayerService
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
            }
            .disabled(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}
