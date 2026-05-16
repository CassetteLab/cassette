// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct OnboardingListenBrainzStepView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void

    @Environment(\.appContainer) private var container
    @State private var vm: ListenBrainzSettingsViewModel?
    @State private var appeared = false
    @State private var showDisconnectAlert = false

    var body: some View {
        ZStack {
            CassetteColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepHeader

                        Group {
                            if let vm {
                                connectionContent(vm: vm)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                            } else {
                                ProgressView()
                                    .padding(.top, CassetteSpacing.xxxxl)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                            }
                        }
                        .padding(.horizontal, CassetteSpacing.l)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.2), value: appeared)

                        Spacer(minLength: 120)
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
            }
        }
        .alert("Disconnect from ListenBrainz?", isPresented: $showDisconnectAlert) {
            if let vm {
                Button("Disconnect", role: .destructive) { Task { await vm.resetCredentials() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your username will be removed. You can reconnect anytime.")
        }
        .onAppear { appeared = true }
        .task {
            guard let container else { return }
            if vm == nil {
                vm = ListenBrainzSettingsViewModel(service: container.listenBrainzService)
            }
            await vm?.refreshSnapshot()
        }
    }

    // MARK: - Header

    private var stepHeader: some View {
        VStack(spacing: CassetteSpacing.l) {
            MergingCirclesHero()
                .padding(.top, CassetteSpacing.xxl)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.7)
                .animation(.spring(duration: 0.6, bounce: 0.4), value: appeared)

            VStack(spacing: CassetteSpacing.xs) {
                Text("Track what you listen to")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(CassetteColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                Text("Connect your ListenBrainz account to log your plays and discover your listening stats.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CassetteColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
            }
            .padding(.horizontal, CassetteSpacing.xxxl)

            stepDots(current: 1, total: 3)
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

    // MARK: - Connection content

    @ViewBuilder
    private func connectionContent(vm: ListenBrainzSettingsViewModel) -> some View {
        let snap = vm.snapshot
        if snap.isEnabled, let username = snap.username {
            connectedCard(vm: vm, username: username)
        } else if let username = snap.username {
            previouslyConnectedCard(vm: vm, username: username)
        } else {
            notConnectedCard(vm: vm)
        }
    }

    private func notConnectedCard(vm: ListenBrainzSettingsViewModel) -> some View {
        @Bindable var vm = vm
        return VStack(spacing: CassetteSpacing.m) {
            VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                Text("ListenBrainz username")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(CassetteColors.textSecondary)

                TextField("your-username", text: $vm.usernameInput)
                    .font(.system(.callout, design: .rounded))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    #endif
                    .onChange(of: vm.usernameInput) { _, _ in
                        vm.validateUsernameInputLocally()
                    }

                if let error = vm.usernameInputValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(CassetteSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                    .fill(CassetteColors.backgroundSecondary)
            )

            Button {
                Task { await vm.connect() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    if vm.isProcessing { ProgressView().scaleEffect(0.8) }
                    Text("Connect to ListenBrainz")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CassetteColors.accent)
            .controlSize(.large)
            .disabled(vm.usernameInput.isEmpty || vm.usernameInputValidationError != nil || vm.isProcessing)

            if let error = vm.userFacingError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func connectedCard(vm: ListenBrainzSettingsViewModel, username: String) -> some View {
        VStack(spacing: CassetteSpacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                    Text("Connected as")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CassetteColors.textSecondary)
                    Text(username)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(CassetteColors.textPrimary)
                }
                Spacer()
                HStack(spacing: CassetteSpacing.xs) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Active")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
            .padding(CassetteSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                    .fill(CassetteColors.backgroundSecondary)
            )

            Button(role: .destructive) {
                showDisconnectAlert = true
            } label: {
                Text("Disconnect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(vm.isProcessing)
        }
    }

    private func previouslyConnectedCard(vm: ListenBrainzSettingsViewModel, username: String) -> some View {
        VStack(spacing: CassetteSpacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                    Text("Previously connected as")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CassetteColors.textSecondary)
                    Text(username)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(CassetteColors.textPrimary)
                }
                Spacer()
            }
            .padding(CassetteSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                    .fill(CassetteColors.backgroundSecondary)
            )

            Button {
                vm.usernameInput = username
                Task { await vm.connect() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    if vm.isProcessing { ProgressView().scaleEffect(0.8) }
                    Text("Reconnect")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CassetteColors.accent)
            .controlSize(.large)
            .disabled(vm.isProcessing)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: CassetteSpacing.m) {
            Button(action: onContinue) {
                Text(vm?.snapshot.isEnabled == true ? "Continue" : "Set Up Later")
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
}

// MARK: - Merging circles hero

private struct MergingCirclesHero: View {
    @State private var merged = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 50)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.55), Color.purple.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 78, height: 78)
                .offset(x: merged ? -20 : -44)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: merged)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.55), Color.indigo.opacity(0.25)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: 78, height: 78)
                .offset(x: merged ? 20 : 44)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: merged)

            Circle()
                .fill(CassetteColors.accent.opacity(merged ? 0.35 : 0))
                .frame(width: 36, height: 36)
                .blur(radius: 10)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: merged)
        }
        .frame(height: 100)
        .onAppear { merged = true }
    }
}
