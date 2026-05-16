// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct OnboardingWelcomeView: View {
    let onServerConnected: () -> Void

    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?
    @State private var showingServerForm = false
    @State private var appeared = false
    @State private var shimmerOffset: CGFloat = -300

    var body: some View {
        ZStack {
            CassetteColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AnimatedCassetteHero()
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .animation(.spring(duration: 0.6, bounce: 0.4), value: appeared)

                Spacer().frame(height: CassetteSpacing.xxxxl)

                VStack(spacing: CassetteSpacing.m) {
                    Text("Your music.\nYour rules.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(CassetteColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                    Text("Stream your library from your own server.\nNo subscriptions. No big tech.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(CassetteColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
                }
                .padding(.horizontal, CassetteSpacing.xxxl)

                Spacer()

                getStartedButton
                    .padding(.horizontal, CassetteSpacing.xxxl)
                    .padding(.bottom, CassetteSpacing.xxxl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.2), value: appeared)
            }
        }
        .onAppear {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    shimmerOffset = 300
                }
            }
        }
        .onChange(of: container?.serverState.activeServer != nil) { _, connected in
            if connected { showingServerForm = false }
        }
        .sheet(isPresented: $showingServerForm, onDismiss: {
            if container?.serverState.activeServer != nil {
                onServerConnected()
            }
        }) {
            if let viewModel {
                NavigationStack {
                    ServerFormView(viewModel: viewModel)
                }
            }
        }
    }

    private var getStartedButton: some View {
        Button {
            triggerHaptic()
            showingServerForm = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(CassetteColors.accent)

                Text("Get Started")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.22), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 80)
                    .offset(x: shimmerOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(viewModel == nil)
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: - Animated Cassette Hero

private struct AnimatedCassetteHero: View {
    @State private var reelAngle: Double = 0

    private let w: CGFloat = 200
    private let h: CGFloat = 130
    private var reelR: CGFloat { w * 0.16 }

    // Reel centers relative to frame center (100, 65)
    private var leftOffset: CGSize {
        CGSize(width: w * 0.285 - w / 2, height: h * 0.40 + reelR / 2 - h / 2)
    }
    private var rightOffset: CGSize {
        CGSize(width: w * 0.715 - w / 2, height: h * 0.40 + reelR / 2 - h / 2)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(CassetteColors.accent.opacity(0.08))
                .frame(width: 290, height: 290)
                .blur(radius: 60)

            ZStack {
                reel
                    .rotationEffect(.degrees(reelAngle))
                    .offset(leftOffset)
                reel
                    .rotationEffect(.degrees(reelAngle))
                    .offset(rightOffset)
            }
            .frame(width: w, height: h)

            CassetteTapeIcon()
                .fill(CassetteColors.backgroundTertiary, style: FillStyle(eoFill: true))
                .frame(width: w, height: h)

            CassetteTapeIcon()
                .stroke(CassetteColors.accent.opacity(0.65), lineWidth: 1.5)
                .frame(width: w, height: h)
        }
        .onAppear {
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                reelAngle = 360
            }
        }
    }

    private var reel: some View {
        ZStack {
            Circle()
                .fill(CassetteColors.backgroundPrimary)
                .frame(width: reelR * 2, height: reelR * 2)
            Circle()
                .stroke(CassetteColors.accent.opacity(0.4), lineWidth: 1)
                .frame(width: reelR * 2, height: reelR * 2)
            Circle()
                .fill(CassetteColors.accentBackground)
                .frame(width: reelR * 0.45, height: reelR * 0.45)
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(CassetteColors.accent.opacity(0.5))
                    .frame(width: 2, height: reelR * 0.62)
                    .offset(y: -(reelR * 0.14))
                    .rotationEffect(.degrees(Double(i) * 120))
            }
        }
    }
}
