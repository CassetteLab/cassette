// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedStatHero: View {
    let data: WrappedData?

    private var heroNumber: String {
        guard let data else { return "—" }
        let minutes = Int(data.totalSecondsListened / 60)
        return minutes >= 60 ? "\(minutes / 60)" : "\(minutes)"
    }

    private var heroUnit: String {
        guard let data else { return "minutes listened" }
        let minutes = Int(data.totalSecondsListened / 60)
        return minutes >= 60 ? "hours listened" : "minutes listened"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            Text(heroNumber)
                .font(.cassettePlayerTitle)
                .foregroundStyle(Color.cassetteAccent)
            Text(heroUnit)
                .font(.cassetteCellTitle)
                .foregroundStyle(.secondary)
            if let data {
                Text("\(data.totalTracksPlayed) plays · \(data.totalUniqueArtists) artist(s)")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(CassetteSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cassetteAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
    }
}
