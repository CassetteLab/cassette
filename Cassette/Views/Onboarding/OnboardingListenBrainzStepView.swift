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
    @State private var showDisconnectAlert = false

    var body: some View {
        OnboardingStepView(
            icon: "link.circle.fill",
            title: "Track what you listen to",
            subtitle: "Connect your ListenBrainz account to log your plays and discover stats.",
            stepIndex: 1,
            totalSteps: 3,
            onSkip: onSkip,
            onContinue: onContinue
        ) {
            if let vm {
                ScrollView {
                    VStack(spacing: CassetteSpacing.m) {
                        connectionContent(vm: vm)
                    }
                    .padding(CassetteSpacing.l)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task {
            guard let container else { return }
            if vm == nil {
                vm = ListenBrainzSettingsViewModel(service: container.listenBrainzService)
            }
            await vm?.refreshSnapshot()
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
                Text("Username")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CassetteColors.textSecondary)
                TextField("your-username", text: $vm.usernameInput)
                    .font(.callout)
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
                        .font(.callout.weight(.semibold))
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
                        .font(.caption)
                        .foregroundStyle(CassetteColors.textSecondary)
                    Text(username)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(CassetteColors.textPrimary)
                }
                Spacer()
                HStack(spacing: CassetteSpacing.xs) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
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
                HStack(spacing: CassetteSpacing.s) {
                    if vm.isProcessing { ProgressView().scaleEffect(0.8) }
                    Text("Disconnect")
                }
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
                        .font(.caption)
                        .foregroundStyle(CassetteColors.textSecondary)
                    Text(username)
                        .font(.callout.weight(.semibold))
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
                        .font(.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CassetteColors.accent)
            .controlSize(.large)
            .disabled(vm.isProcessing)
        }
    }
}
