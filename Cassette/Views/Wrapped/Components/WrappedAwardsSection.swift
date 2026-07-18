// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedAwardsSection: View {
    let data: WrappedData
    private let awards: [AwardEntry]

    @State private var focusedId: Int? = 0

    init(data: WrappedData) {
        self.data = data
        let (minuteStr, _) = data.totalSecondsListened.wrappedHeroMinutesFormat()
        awards = [
            AwardEntry(id: 0, icon: .cassette, title: String(localized: "Time Devoted"), value: minuteStr, subline: String(localized: "minutes listened")),
            AwardEntry(id: 1, icon: .sf("flame.fill"), title: String(localized: "Daily Habit"), value: "\(data.streakDays)", subline: data.streakDays == 1 ? String(localized: "day streak") : String(localized: "days streak")),
            AwardEntry(id: 2, icon: .sf("music.note"), title: String(localized: "Discovery"), value: "\(data.totalUniqueTracks)", subline: data.totalUniqueTracks == 1 ? String(localized: "unique track") : String(localized: "unique tracks")),
            AwardEntry(id: 3, icon: .sf("person.2.fill"), title: String(localized: "Variety"), value: "\(data.totalUniqueArtists)", subline: data.totalUniqueArtists == 1 ? String(localized: "artist heard") : String(localized: "artists heard")),
            AwardEntry(id: 4, icon: .sf("guitars.fill"), title: String(localized: "Style"), value: data.dominantGenre ?? "—", subline: String(localized: "dominant genre")),
        ]
    }

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
}
