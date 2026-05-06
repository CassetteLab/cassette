// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedIntroSlide: View {
    let year: Int
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: CassetteSpacing.xs) {
                    Text("YOUR")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("\(year)")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .kerning(-3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("Wrapped")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .kerning(-1)
                        .foregroundStyle(.white)
                }

                Spacer()
                Spacer()

                Text("Your year in music.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, CassetteSpacing.xxxxl)
            }
            .padding(.horizontal, CassetteSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
