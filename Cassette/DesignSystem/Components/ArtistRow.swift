// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// List cell for an artist. Avatar uses the artist's initials on an accent-tinted circle
/// (Subsonic rarely provides artist artwork, so a generic placeholder is the baseline).
struct ArtistRow: View {
    let artist: ArtistID3

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            initialsAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let count = artist.albumCount {
                    Text("\(count) album\(count == 1 ? "" : "s")")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.cassetteAccentSecondary, Color.cassetteAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.cassetteAccentText)
        }
        .frame(width: 44, height: 44)
    }

    private var initials: String {
        let words = artist.name.split(separator: " ")
        switch words.count {
        case 0: return "?"
        case 1: return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
    }
}
