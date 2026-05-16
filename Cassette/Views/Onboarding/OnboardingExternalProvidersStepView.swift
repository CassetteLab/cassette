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
    @State private var appeared = false
    @State private var showingAdd = false
    @State private var editingProvider: ExternalReleaseProvider?

    var body: some View {
        ZStack {
            CassetteColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepHeader

                        Group {
                            if let vm {
                                providersContent(vm: vm)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                            } else {
                                ProgressView()
                                    .padding(.top, CassetteSpacing.xxxxl)
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
            appeared = true
        }
    }

    // MARK: - Header

    private var stepHeader: some View {
        VStack(spacing: CassetteSpacing.l) {
            BouncingIconHero()
                .padding(.top, CassetteSpacing.xxl)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.7)
                .animation(.spring(duration: 0.6, bounce: 0.4), value: appeared)

            VStack(spacing: CassetteSpacing.xs) {
                Text("Open releases your way")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(CassetteColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                Text("Add a provider to look up albums on Discogs,\nMusicBrainz, or anywhere you like.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CassetteColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
            }
            .padding(.horizontal, CassetteSpacing.xxxl)

            stepDots(current: 2, total: 3)
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

    // MARK: - Providers content

    @ViewBuilder
    private func providersContent(vm: ExternalProvidersSettingsViewModel) -> some View {
        VStack(spacing: CassetteSpacing.m) {
            if vm.providers.isEmpty {
                emptyState
            } else {
                ForEach(vm.providers) { provider in
                    providerRow(provider: provider, vm: vm)
                }
            }

            Button {
                showingAdd = true
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(CassetteColors.accent)
                    Text("Add Provider")
                        .font(.system(.callout, design: .rounded, weight: .medium))
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

    private var emptyState: some View {
        VStack(spacing: CassetteSpacing.s) {
            Text("No providers yet")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(CassetteColors.textSecondary)
            Text("Releases open in ListenBrainz by default.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CassetteColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CassetteSpacing.xxl)
        .padding(.horizontal, CassetteSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(CassetteColors.backgroundSecondary)
        )
    }

    private func providerRow(provider: ExternalReleaseProvider, vm: ExternalProvidersSettingsViewModel) -> some View {
        Button {
            editingProvider = provider
        } label: {
            HStack {
                Text(provider.name)
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(CassetteColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(CassetteColors.textTertiary)
            }
            .padding(CassetteSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                    .fill(CassetteColors.backgroundSecondary)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { editingProvider = provider }
            Button("Delete", role: .destructive) { vm.delete(provider) }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: CassetteSpacing.m) {
            Button(action: onContinue) {
                Text("Done")
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

// MARK: - Bouncing icon hero

private struct BouncingIconHero: View {
    @State private var bouncing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 50)

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 96, height: 96)

                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            .scaleEffect(bouncing ? 1.08 : 0.94)
            .offset(y: bouncing ? -5 : 5)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: bouncing)
        }
        .frame(height: 110)
        .onAppear { bouncing = true }
    }
}
