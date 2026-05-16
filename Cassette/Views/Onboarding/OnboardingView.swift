// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

private enum OnboardingStep {
    case welcome, cache, listenBrainz, externalProviders
}

struct OnboardingView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?
    @State private var showingServerForm = false
    @State private var step: OnboardingStep = .welcome
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            switch step {
            case .welcome:
                welcomeView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            case .cache:
                OnboardingCacheStepView(
                    onSkip: { step = .listenBrainz },
                    onContinue: { step = .listenBrainz }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .listenBrainz:
                OnboardingListenBrainzStepView(
                    onSkip: { step = .externalProviders },
                    onContinue: { step = .externalProviders }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .externalProviders:
                OnboardingExternalProvidersStepView(
                    onSkip: { onboardingComplete = true },
                    onContinue: { onboardingComplete = true }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .task {
            // Existing users upgrading: server already set, skip all onboarding steps.
            if container?.serverState.activeServer != nil {
                onboardingComplete = true
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        ZStack {
            CassetteColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(CassetteColors.accent.opacity(0.12))
                        .frame(width: 180, height: 180)
                        .blur(radius: 50)

                    ZStack {
                        Circle()
                            .fill(CassetteColors.accentBackground)
                            .frame(width: 96, height: 96)

                        CassetteTapeIcon()
                            .fill(CassetteColors.accent, style: FillStyle(eoFill: true))
                            .frame(width: 52, height: 34)
                    }
                }

                Spacer().frame(height: CassetteSpacing.xxxxl)

                VStack(spacing: CassetteSpacing.m) {
                    Text("Your music.\nYour server.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(CassetteColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("Stream your Navidrome library on iPhone and Mac.\nNo subscriptions, no big tech.")
                        .font(.body)
                        .foregroundStyle(CassetteColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, CassetteSpacing.xxxl)

                Spacer()

                Button {
                    showingServerForm = true
                } label: {
                    Text("Add Server")
                        .font(.system(.body, design: .default, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(CassetteColors.accent)
                .disabled(viewModel == nil)
                .padding(.horizontal, CassetteSpacing.xxxl)
                .padding(.bottom, CassetteSpacing.xxxl)
            }
        }
        .onAppear {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
        }
        .onChange(of: container?.serverState.activeServer != nil) { _, serverConnected in
            if serverConnected { showingServerForm = false }
        }
        .sheet(isPresented: $showingServerForm, onDismiss: {
            if container?.serverState.activeServer != nil {
                step = .cache
            }
        }) {
            if let viewModel {
                NavigationStack {
                    ServerFormView(viewModel: viewModel)
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
