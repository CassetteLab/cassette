// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct OnboardingCacheStepView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void

    @Environment(\.appContainer) private var container
    @State private var appeared = false

    var body: some View {
        ZStack {
            CassetteColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepHeader
                        if let settings = container?.cacheSettings {
                            cacheContent(settings: settings)
                                .padding(.horizontal, CassetteSpacing.l)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 24)
                                .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.2), value: appeared)
                        }
                        Spacer(minLength: 120)
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
            }
        }
        .onAppear { appeared = true }
    }

    // MARK: - Header

    private var stepHeader: some View {
        VStack(spacing: CassetteSpacing.l) {
            WaveformHero()
                .padding(.top, CassetteSpacing.xxl)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.7)
                .animation(.spring(duration: 0.6, bounce: 0.4), value: appeared)

            VStack(spacing: CassetteSpacing.xs) {
                Text("Speed things up")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(CassetteColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                Text("Keep your recent tracks ready instantly,\neven on a slow connection.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CassetteColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
            }
            .padding(.horizontal, CassetteSpacing.xxxl)

            stepDots(current: 0, total: 3)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.15), value: appeared)
        }
        .padding(.bottom, CassetteSpacing.xxl)
    }

    private func stepDots(current: Int, total: Int) -> some View {
        HStack(spacing: CassetteSpacing.s) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? CassetteColors.accent : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 20 : 6, height: 6)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func cacheContent(settings: CacheSettings) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            maxTracksCard(settings: settings)
            formatPills(settings: settings)
            cellularToggle(settings: settings)
        }
    }

    private func maxTracksCard(settings: CacheSettings) -> some View {
        VStack(spacing: CassetteSpacing.s) {
            Text("Tracks to cache")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(CassetteColors.textSecondary)

            HStack(spacing: CassetteSpacing.xxl) {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        settings.maxTracks = max(CacheSettings.minMaxTracks, settings.maxTracks - 1)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title)
                        .foregroundStyle(
                            settings.maxTracks <= CacheSettings.minMaxTracks
                                ? CassetteColors.textTertiary : CassetteColors.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(settings.maxTracks <= CacheSettings.minMaxTracks)

                Text("\(settings.maxTracks)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(CassetteColors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: settings.maxTracks)
                    .frame(minWidth: 90, alignment: .center)

                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        settings.maxTracks = min(CacheSettings.maxMaxTracks, settings.maxTracks + 1)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(
                            settings.maxTracks >= CacheSettings.maxMaxTracks
                                ? CassetteColors.textTertiary : CassetteColors.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(settings.maxTracks >= CacheSettings.maxMaxTracks)
            }

            Text("Oldest track replaced when limit is reached")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(CassetteColors.textTertiary)
        }
        .padding(.vertical, CassetteSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    private func formatPills(settings: CacheSettings) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Cache format")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(CassetteColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CassetteSpacing.s) {
                    ForEach(CacheFormat.allCases) { format in
                        Button {
                            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                settings.cacheFormat = format
                            }
                        } label: {
                            Text(formatShortName(format))
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(
                                    settings.cacheFormat == format ? .white : CassetteColors.textSecondary
                                )
                                .padding(.horizontal, CassetteSpacing.l)
                                .padding(.vertical, CassetteSpacing.s)
                                .background(
                                    Capsule()
                                        .fill(
                                            settings.cacheFormat == format
                                                ? CassetteColors.accent : CassetteColors.backgroundSecondary
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func cellularToggle(settings: CacheSettings) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("Use cellular data")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(CassetteColors.textPrimary)
                Text("Allow caching when not on Wi‑Fi")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CassetteColors.textSecondary)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { settings.cacheOverCellular },
                    set: { settings.cacheOverCellular = $0 }
                )
            )
            .labelsHidden()
            .tint(CassetteColors.accent)
        }
        .padding(CassetteSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: CassetteSpacing.m) {
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(CassetteColors.accent)

            Button("Skip", action: onSkip)
                .font(.subheadline)
                .foregroundStyle(CassetteColors.textSecondary)
        }
        .padding(.horizontal, CassetteSpacing.xxxl)
        .padding(.top, CassetteSpacing.l)
        .padding(.bottom, CassetteSpacing.xxl)
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func formatShortName(_ format: CacheFormat) -> String {
        switch format {
        case .matchStream:  return "Auto"
        case .flacOriginal: return "FLAC"
        case .mp3_320:      return "MP3 320"
        case .mp3_192:      return "MP3 192"
        case .opus_128:     return "Opus"
        }
    }
}

// MARK: - Waveform hero

private struct WaveformHero: View {
    @State private var animate = false

    private let heights: [CGFloat] = [28, 52, 38, 72, 44, 56, 30]
    private let delays: [Double]   = [0.0, 0.12, 0.22, 0.06, 0.17, 0.09, 0.20]
    private let durations: [Double] = [0.72, 0.65, 0.78, 0.60, 0.70, 0.68, 0.75]

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(CassetteColors.accent.opacity(0.35 + Double(i % 3) * 0.18))
                    .frame(width: 9, height: animate ? heights[i] : heights[i] * 0.28)
                    .animation(
                        .easeInOut(duration: durations[i])
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: animate
                    )
            }
        }
        .frame(height: 90)
        .onAppear { animate = true }
    }
}
