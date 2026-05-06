// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedAwardMedal: View {
    enum MedalIcon {
        case cassetteTape
        case system(String)
    }

    let icon: MedalIcon
    let headline: String
    let subline: String
    let palette: [Color]

    var body: some View {
        VStack(spacing: CassetteSpacing.m) {
            badge
            labels
        }
        .frame(width: 160)
        .padding(.vertical, CassetteSpacing.l)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(holoGradient)
            Circle()
                .fill(Color(.systemBackground))
                .padding(11)
            iconView
        }
        .frame(width: 96, height: 96)
    }

    private var labels: some View {
        VStack(spacing: CassetteSpacing.xs) {
            Text(headline)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(subline)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var holoGradient: AngularGradient {
        guard palette.count >= 3 else {
            return AngularGradient(colors: [.gray], center: .center)
        }
        return AngularGradient(
            stops: [
                .init(color: palette[0], location: 0.00),
                .init(color: palette[1], location: 0.33),
                .init(color: palette[2], location: 0.66),
                .init(color: palette[0], location: 1.00),
            ],
            center: .center
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .cassetteTape:
            CassetteTapeIcon()
                .fill(.primary, style: FillStyle(eoFill: true))
                .frame(width: 42, height: 28)
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    let palette = WrappedYearPalette.colors(for: 2026)
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            WrappedAwardMedal(icon: .cassetteTape, headline: "1 234", subline: "minutes listened", palette: palette)
            WrappedAwardMedal(icon: .system("flame.fill"), headline: "12", subline: "day streak", palette: palette)
            WrappedAwardMedal(icon: .system("music.note"), headline: "342", subline: "unique tracks", palette: palette)
            WrappedAwardMedal(icon: .system("person.2.fill"), headline: "48", subline: "artists discovered", palette: palette)
            WrappedAwardMedal(icon: .system("guitars.fill"), headline: "Rock", subline: "dominant genre", palette: palette)
        }
        .padding(.horizontal, CassetteSpacing.l)
    }
}
