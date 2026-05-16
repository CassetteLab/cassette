// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedAwardsSection: View {
    let data: WrappedData

    @State private var focusedId: Int? = 0

    private var palette: [Color] {
        WrappedYearPalette.colors(for: data.period.calendarYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.m) {
            Text("Awards")
                .font(.cassetteSectionTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CassetteSpacing.m) {
                    ForEach(awards) { award in
                        carouselCell(award)
                            .id(award.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, CassetteSpacing.l, for: .scrollContent)
            .padding(.horizontal, -CassetteSpacing.l)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedId)
        }
        .padding(.vertical, CassetteSpacing.m)
    }

    private func carouselCell(_ award: AwardEntry) -> some View {
        VStack(spacing: CassetteSpacing.s) {
            WrappedAwardMedal(
                icon: award.icon,
                value: award.value,
                palette: palette,
                isFocused: focusedId == award.id
            )
            Text(award.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(award.subline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 160)
    }

    // MARK: - Award data

    private struct AwardEntry: Identifiable {
        let id: Int
        let icon: AwardIcon
        let title: String
        let value: String
        let subline: String
    }

    private var awards: [AwardEntry] {
        let (minuteStr, _) = data.totalSecondsListened.wrappedHeroMinutesFormat()
        return [
            AwardEntry(
                id: 0, icon: .cassette,
                title: "Time Devoted",
                value: minuteStr,
                subline: "minutes listened"
            ),
            AwardEntry(
                id: 1, icon: .sf("flame.fill"),
                title: "Daily Habit",
                value: "\(data.streakDays)",
                subline: data.streakDays == 1 ? "day streak" : "days streak"
            ),
            AwardEntry(
                id: 2, icon: .sf("music.note"),
                title: "Discovery",
                value: "\(data.totalUniqueTracks)",
                subline: data.totalUniqueTracks == 1 ? "unique track" : "unique tracks"
            ),
            AwardEntry(
                id: 3, icon: .sf("person.2.fill"),
                title: "Variety",
                value: "\(data.totalUniqueArtists)",
                subline: data.totalUniqueArtists == 1 ? "artist heard" : "artists heard"
            ),
            AwardEntry(
                id: 4, icon: .sf("guitars.fill"),
                title: "Style",
                value: data.dominantGenre ?? "—",
                subline: "dominant genre"
            ),
        ]
    }
}
