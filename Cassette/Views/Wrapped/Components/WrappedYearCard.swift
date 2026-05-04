// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedYearCard: View {
    let year: Int

    private var shortYear: String { "'\(String(year).suffix(2))" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.cassetteAccent, Color.cassetteAccent.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("Cassette Wrapped \(shortYear)")
                    .font(.cassetteDetailTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.cassetteAccentText)
                Text("Your year in music")
                    .font(.cassetteCaption)
                    .foregroundStyle(Color.cassetteAccentText.opacity(0.80))
            }
            .padding(CassetteSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
    }
}
