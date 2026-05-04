// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedRewardsSection: View {
    let data: WrappedData?

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Highlights")
                .font(.cassetteSectionTitle)
            HStack(spacing: CassetteSpacing.m) {
                rewardPill(
                    icon: "flame.fill",
                    label: streakLabel,
                    color: .orange
                )
                if let genre = data?.dominantGenre {
                    rewardPill(icon: "music.note", label: genre, color: Color.cassetteAccent)
                }
            }
        }
    }

    private var streakLabel: String {
        guard let days = data?.streakDays, days > 0 else { return "No streak yet" }
        return "\(days) day streak"
    }

    private func rewardPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: CassetteSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.cassetteCaption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.s)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}
