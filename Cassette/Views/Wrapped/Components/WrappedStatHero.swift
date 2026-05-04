// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftUI

struct WrappedStatHero: View {
    let data: WrappedData

    @State private var animatedSeconds: TimeInterval = 0

    var body: some View {
        let palette = WrappedYearPalette.colors(for: data.period.calendarYear)

        MeshGradientBackground(palette: palette, animated: true)
            .frame(minHeight: 340)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                heroContent
            }
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.hero, style: .continuous))
            .onAppear { triggerAnimation() }
            .onChange(of: data.totalSecondsListened) { _, _ in triggerAnimation() }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnimatedHeroText(seconds: animatedSeconds)

            Color.white.opacity(0.2)
                .frame(maxWidth: .infinity)
                .frame(height: 1)
                .padding(.vertical, CassetteSpacing.m)

            HStack(spacing: CassetteSpacing.xs) {
                Text(data.totalTracksPlayed.plural("play", "plays"))
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(data.totalUniqueArtists.plural("artist", "artists"))
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(data.totalUniqueAlbums.plural("album", "albums"))
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, CassetteSpacing.xl)
        .padding(.vertical, CassetteSpacing.l)
    }

    private func triggerAnimation() {
        Logger.wrapped.debug("[WRAPPED-HERO] counter animation triggered seconds=\(data.totalSecondsListened, privacy: .public)")
        animatedSeconds = 0
        withAnimation(.spring(response: 1.2, dampingFraction: 0.8)) {
            animatedSeconds = data.totalSecondsListened
        }
    }
}

// MARK: - Animated counter sub-view

private struct AnimatedHeroText: View, Animatable {
    var seconds: Double

    var animatableData: Double {
        get { seconds }
        set { seconds = newValue }
    }

    var body: some View {
        let (number, unit) = seconds.wrappedHeroFormat()
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            Text(number)
                .font(.system(size: 96, weight: .black, design: .rounded))
                .kerning(-2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
