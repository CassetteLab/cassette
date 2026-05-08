// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Discover carousel card for the current Wrapped year when no playlist exists yet.
///
/// Two states (caller guarantees the card is within the Dec 3 – Jan 1 window):
/// - **Countdown** (Dec 3–27): shows days remaining, non-interactive.
/// - **Unlocked** (≥ Dec 28): play button opens `WrappedStoryPlayerView`.
struct WrappedCurrentYearCard: View {
    let year: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStoryPlayer = false
    @State private var pulse = false

    private var palette: [Color] { WrappedYearPalette.colors(for: year) }
    private var isUnlocked: Bool { WrappedStoryAvailability.isStoryAvailable(forYear: year) }
    private var daysLeft: Int { WrappedStoryAvailability.daysUntilStoryUnlock(forYear: year) ?? 0 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)
                .frame(width: 140, height: 160)
                .overlay { cardOverlay }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))

            if isUnlocked {
                Button {
                    showStoryPlayer = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .padding(CassetteSpacing.s)
            }
        }
        .fullScreenCover(isPresented: $showStoryPlayer) {
            WrappedStoryPlayerView(year: year)
        }
    }

    @ViewBuilder
    private var cardOverlay: some View {
        if isUnlocked {
            unlockedOverlay
        } else {
            countdownOverlay
        }
    }

    // MARK: - Unlocked overlay (mirrors WrappedYearlyCard layout)

    private var unlockedOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            Text(String(year))
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("Wrapped")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CassetteSpacing.s)
    }

    // MARK: - Countdown overlay

    private var countdownOverlay: some View {
        VStack(spacing: 0) {
            CassetteTapeIcon()
                .fill(.white.opacity(0.45), style: FillStyle(eoFill: true))
                .frame(width: 38, height: 25)
                .scaleEffect(pulse ? 1.07 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }
                .padding(.top, CassetteSpacing.m)

            Spacer()

            VStack(spacing: 1) {
                Text("Plus que")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(daysLeft)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(daysLeft == 1 ? "jour" : "jours")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text("Avant ton Wrapped \(year)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, CassetteSpacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CassetteSpacing.xs)
    }
}
