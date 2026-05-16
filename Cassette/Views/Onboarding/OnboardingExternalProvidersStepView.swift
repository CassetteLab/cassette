// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct OnboardingExternalProvidersStepView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void
    @Environment(\.appContainer) private var container
    @State private var vm: ExternalProvidersSettingsViewModel?
    @State private var showingAdd = false
    @State private var editingProvider: ExternalReleaseProvider?

    var body: some View {
        OnboardingStepView(
            icon: "arrow.up.right.square.fill",
            title: "Open releases your way",
            subtitle: "Add a custom search provider to look up albums on Discogs, MusicBrainz, or anywhere else.",
            stepIndex: 2,
            totalSteps: 3,
            onSkip: onSkip,
            onContinue: onContinue
        ) {
            if let vm {
                ScrollView {
                    VStack(spacing: CassetteSpacing.m) {
                        providersContent(vm: vm)
                    }
                    .padding(CassetteSpacing.l)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAdd) {
            if let vm {
                NavigationStack {
                    ExternalProviderEditView(mode: .new) { vm.save($0) }
                }
            }
        }
        .sheet(item: $editingProvider) { provider in
            if let vm {
                NavigationStack {
                    ExternalProviderEditView(mode: .edit(provider), onSave: { vm.save($0) }) {
                        vm.delete(provider)
                    }
                }
            }
        }
        .onAppear {
            if vm == nil, let store = container?.externalProvidersStore {
                vm = ExternalProvidersSettingsViewModel(store: store)
            }
        }
    }

    // MARK: - Providers content

    @ViewBuilder
    private func providersContent(vm: ExternalProvidersSettingsViewModel) -> some View {
        if vm.providers.isEmpty {
            emptyProvidersCard
        } else {
            ForEach(vm.providers) { provider in
                providerCard(provider: provider, vm: vm)
            }
        }
        addProviderButton
    }

    private var emptyProvidersCard: some View {
        VStack(spacing: CassetteSpacing.s) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 28))
                .foregroundStyle(CassetteColors.textTertiary)
            Text("No providers configured")
                .font(.callout.weight(.medium))
                .foregroundStyle(CassetteColors.textSecondary)
            Text("Releases open in ListenBrainz by default.")
                .font(.caption)
                .foregroundStyle(CassetteColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(CassetteSpacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    private func providerCard(provider: ExternalReleaseProvider, vm: ExternalProvidersSettingsViewModel) -> some View {
        HStack {
            Text(provider.name)
                .font(.callout.weight(.medium))
                .foregroundStyle(CassetteColors.textPrimary)
            Spacer()
            Button {
                editingProvider = provider
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(CassetteColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(CassetteSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    private var addProviderButton: some View {
        Button {
            showingAdd = true
        } label: {
            HStack(spacing: CassetteSpacing.s) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(CassetteColors.accent)
                Text("Add Provider")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(CassetteColors.accent)
                Spacer()
            }
            .padding(CassetteSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                    .fill(CassetteColors.accentBackground)
            )
        }
        .buttonStyle(.plain)
    }
}
