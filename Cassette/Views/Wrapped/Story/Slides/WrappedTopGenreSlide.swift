// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopGenreSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: CassetteSpacing.xxxxl)

                Text("YOUR SOUND")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your most-played")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("genre was")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: CassetteSpacing.l)

                Text(data.dominantGenre ?? "Mixed")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .kerning(-1.5)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)

                Spacer()
            }
            .padding(.horizontal, CassetteSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
