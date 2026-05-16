// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct OnboardingCacheStepView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void
    @Environment(\.appContainer) private var container

    var body: some View {
        OnboardingStepView(
            icon: "externaldrive.fill",
            title: "Speed things up",
            subtitle: "Keep your recent tracks ready to play instantly, even on a slow connection.",
            stepIndex: 0,
            totalSteps: 3,
            onSkip: onSkip,
            onContinue: onContinue
        ) {
            if let settings = container?.cacheSettings {
                ScrollView {
                    VStack(spacing: CassetteSpacing.m) {
                        maxTracksCard(settings: settings)
                        formatCard(settings: settings)
                        cellularCard(settings: settings)
                    }
                    .padding(CassetteSpacing.l)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Cards

    private func maxTracksCard(settings: CacheSettings) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("Max cached tracks")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(CassetteColors.textPrimary)
                Text("Oldest track replaced when limit is reached")
                    .font(.caption)
                    .foregroundStyle(CassetteColors.textSecondary)
            }
            Spacer(minLength: 0)
            Text("\(settings.maxTracks)")
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(CassetteColors.textPrimary)
                .frame(minWidth: 24, alignment: .trailing)
            Stepper(
                "",
                value: Binding(
                    get: { settings.maxTracks },
                    set: { settings.maxTracks = $0 }
                ),
                in: CacheSettings.minMaxTracks...CacheSettings.maxMaxTracks
            )
            .labelsHidden()
        }
        .padding(CassetteSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    private func formatCard(settings: CacheSettings) -> some View {
        HStack {
            Text("Format")
                .font(.callout.weight(.medium))
                .foregroundStyle(CassetteColors.textPrimary)
            Spacer()
            Picker(
                "Format",
                selection: Binding(
                    get: { settings.cacheFormat },
                    set: { settings.cacheFormat = $0 }
                )
            ) {
                ForEach(CacheFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(CassetteSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    private func cellularCard(settings: CacheSettings) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("Use cellular data")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(CassetteColors.textPrimary)
                Text("Allow caching when not on Wi‑Fi")
                    .font(.caption)
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
}
