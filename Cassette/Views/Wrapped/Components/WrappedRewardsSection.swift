// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedRewardsSection: View {
    let data: WrappedData

    private struct HighlightCard {
        let icon: String
        let headline: String
        let subline: String
        let color: Color
    }

    private var cards: [HighlightCard] {
        var result: [HighlightCard] = []

        if data.streakDays > 0 {
            result.append(.init(
                icon: "flame.fill",
                headline: "\(data.streakDays)",
                subline: data.streakDays == 1 ? "day in a row" : "days in a row",
                color: .orange
            ))
        }

        let (heroNumber, heroUnit) = data.totalSecondsListened.wrappedHeroFormat()
        result.append(.init(
            icon: "headphones",
            headline: heroNumber,
            subline: heroUnit,
            color: Color.cassetteAccent
        ))

        result.append(.init(
            icon: "music.note",
            headline: "\(data.totalUniqueTracks)",
            subline: data.totalUniqueTracks == 1 ? "unique track" : "unique tracks",
            color: Color.cassetteAccent
        ))

        result.append(.init(
            icon: "person.2.fill",
            headline: "\(data.totalUniqueArtists)",
            subline: data.totalUniqueArtists == 1 ? "artist heard" : "artists heard",
            color: Color.cassetteAccent
        ))

        if let genre = data.dominantGenre {
            result.append(.init(
                icon: "guitars.fill",
                headline: genre,
                subline: "top genre",
                color: Color.cassetteAccent
            ))
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Highlights")
                .font(.cassetteSectionTitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CassetteSpacing.m) {
                    ForEach(Array(cards.prefix(5).enumerated()), id: \.offset) { _, card in
                        highlightCard(card)
                    }
                }
                .padding(.horizontal, CassetteSpacing.l)
            }
            .padding(.horizontal, -CassetteSpacing.l)
        }
    }

    private func highlightCard(_ card: HighlightCard) -> some View {
        VStack(spacing: CassetteSpacing.s) {
            ZStack {
                Circle()
                    .fill(card.color.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: card.icon)
                    .font(.title2)
                    .foregroundStyle(card.color)
            }
            Text(card.headline)
                .font(.cassetteCellTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(card.subline)
                .font(.cassetteCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 100)
    }
}
