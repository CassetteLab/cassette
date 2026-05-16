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
            case .cache:
                cacheStep
            case .listenBrainz:
                listenBrainzStep
            case .externalProviders:
                externalProvidersStep
            }
        }
        .task {
            // Existing users upgrading: server already set, skip all onboarding steps.
            if container?.serverState.activeServer != nil {
                onboardingComplete = true
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hifispeaker.2")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Welcome to Cassette")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Connect to your Subsonic-compatible music server to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Add Server") {
                showingServerForm = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel == nil)
        }
        .padding(32)
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

    // MARK: - Cache

    private var cacheStep: some View {
        NavigationStack {
            Form {
                CacheSectionView()
            }
            .formStyle(.grouped)
            .navigationTitle("Cache")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { step = .listenBrainz }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { step = .listenBrainz }
                }
            }
        }
    }

    // MARK: - ListenBrainz

    private var listenBrainzStep: some View {
        NavigationStack {
            ListenBrainzSettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { step = .externalProviders }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue") { step = .externalProviders }
                    }
                }
        }
    }

    // MARK: - External Providers

    private var externalProvidersStep: some View {
        NavigationStack {
            ExternalProvidersSettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { onboardingComplete = true }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onboardingComplete = true }
                    }
                }
        }
    }
}

#Preview {
    OnboardingView()
}
