// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

enum AwardIcon {
    case sf(String)
    case cassette
}

struct WrappedAwardMedal: View {
    let icon: AwardIcon
    let value: String
    let palette: [Color]
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spinEnabled: Bool { isFocused && !reduceMotion }

    var body: some View {
        ZStack {
            outerRing

            // Intermediate accent ring
            Circle()
                .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                .frame(width: 116, height: 116)

            // Central radial circle
            Circle()
                .fill(centralGradient)
                .frame(width: 100, height: 100)

            // Metal polish — top highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 100, height: 100)

            // Metal polish — bottom shadow
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.10)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .frame(width: 100, height: 100)

            // Icon + value
            VStack(spacing: 4) {
                iconView
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                    .shadow(color: .white.opacity(0.15), radius: 0, x: 0, y: -1)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Outer ring

    @ViewBuilder
    private var outerRing: some View {
        if spinEnabled {
            // TimelineView drives rotation from absolute time — no seam at cycle boundary.
            TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let degrees = (elapsed / 12.0).truncatingRemainder(dividingBy: 1) * 360
                Circle()
                    .strokeBorder(holoGradient, lineWidth: 12)
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(degrees))
            }
        } else {
            Circle()
                .strokeBorder(holoGradient, lineWidth: 12)
                .frame(width: 140, height: 140)
        }
    }

    // MARK: - Gradients

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

    private var centralGradient: RadialGradient {
        RadialGradient(
            colors: [
                .white.opacity(0.30),
                (palette.last ?? palette[0]).opacity(0.10),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 50
        )
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .cassette:
            CassetteTapeIcon()
                .fill(.white, style: FillStyle(eoFill: true))
                .frame(width: 38, height: 25)
                .shadow(color: .white.opacity(0.3), radius: 4)
        case .sf(let name):
            Image(systemName: name)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.3), radius: 4)
        }
    }
}

#Preview {
    let palette = WrappedYearPalette.colors(for: 2026)
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: CassetteSpacing.l) {
            WrappedAwardMedal(icon: .cassette,            value: "45",  palette: palette, isFocused: true)
            WrappedAwardMedal(icon: .sf("flame.fill"),    value: "7",   palette: palette, isFocused: false)
            WrappedAwardMedal(icon: .sf("music.note"),    value: "127", palette: palette, isFocused: false)
            WrappedAwardMedal(icon: .sf("person.2.fill"), value: "42",  palette: palette, isFocused: false)
            WrappedAwardMedal(icon: .sf("guitars.fill"),  value: "Pop", palette: palette, isFocused: false)
        }
        .padding(.horizontal, CassetteSpacing.l)
        .padding(.vertical, CassetteSpacing.xl)
    }
    .background(Color(.systemBackground))
}
