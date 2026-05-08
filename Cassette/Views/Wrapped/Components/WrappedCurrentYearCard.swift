// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Discover carousel card for the current Wrapped year when no playlist exists yet.
///
/// - **Locked** (before Dec 28): card visible, lock icon signals story isn't available yet.
/// - **Unlocked** (≥ Dec 28): play button opens `WrappedStoryPlayerView`.
struct WrappedCurrentYearCard: View {
    let year: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStoryPlayer = false

    private var palette: [Color] { WrappedYearPalette.colors(for: year) }
    private var isUnlocked: Bool { WrappedStoryAvailability.isStoryAvailable(forYear: year) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)
                .frame(width: 140, height: 160)
                .overlay { cardOverlay }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))

            Button {
                guard isUnlocked else { return }
                showStoryPlayer = true
            } label: {
                Image(systemName: isUnlocked ? "play.circle.fill" : "lock.circle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .opacity(isUnlocked ? 1.0 : 0.45)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(CassetteSpacing.s)
        }
        .fullScreenCover(isPresented: $showStoryPlayer) {
            WrappedStoryPlayerView(year: year)
        }
    }

    private var cardOverlay: some View {
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
}
