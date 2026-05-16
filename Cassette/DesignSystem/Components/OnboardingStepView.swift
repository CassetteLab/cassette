// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Reusable layout container for optional onboarding steps.
/// Renders a branded header (icon + title + subtitle + progress dots),
/// the step's settings content in a scrollable middle area, and
/// Skip / Continue buttons pinned at the bottom via safeAreaInset.
struct OnboardingStepView<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let stepIndex: Int
    let totalSteps: Int
    let onSkip: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: () -> Content

    private var continueLabel: String {
        stepIndex == totalSteps - 1 ? "Done" : "Continue"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .background(CassetteColors.backgroundPrimary)
            content()
                .safeAreaInset(edge: .bottom) {
                    bottomActions
                }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: CassetteSpacing.m) {
            ZStack {
                Circle()
                    .fill(CassetteColors.accentBackground)
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(CassetteColors.accent)
            }

            VStack(spacing: CassetteSpacing.xs) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CassetteColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(CassetteColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, CassetteSpacing.xxxl)

            progressDots
        }
        .padding(.top, CassetteSpacing.xxl)
        .padding(.bottom, CassetteSpacing.l)
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: CassetteSpacing.s) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? CassetteColors.accent : Color.secondary.opacity(0.3))
                    .frame(width: i == stepIndex ? 20 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: stepIndex)
            }
        }
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: CassetteSpacing.m) {
            Button(action: onContinue) {
                Text(continueLabel)
                    .font(.system(.body, design: .default, weight: .semibold))
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
}
