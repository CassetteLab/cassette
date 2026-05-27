// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ListenBrainzSettingsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ListenBrainzSettingsViewModel?
    @State private var showForgetAlert = false

    var body: some View {
        Group {
            if let vm = viewModel {
                Form {
                    aboutSection()
                    connectionSection(vm: vm)
                }
                .formStyle(.grouped)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("ListenBrainz")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        #endif
        .task {
            guard let container else { return }
            if viewModel == nil {
                viewModel = ListenBrainzSettingsViewModel(service: container.listenBrainzService)
            }
            await viewModel?.refreshSnapshot()
        }
    }

    // MARK: - About

    private func aboutSection() -> some View {
        Section {
            Text("ListenBrainz is an open-source music recommendation service by the MetaBrainz Foundation. Cassette uses it (read-only) to surface fresh releases and similar artists. Your listening history is **not** sent from Cassette — scrobbling stays on your Navidrome server.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Visit ListenBrainz →") {
                ExternalLinkOpener.open(CassetteURLs.listenBrainz)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.footnote)
        } header: {
            Text("About ListenBrainz")
        }
    }

    // MARK: - Connection

    @ViewBuilder
    private func connectionSection(vm: ListenBrainzSettingsViewModel) -> some View {
        let snap = vm.snapshot
        if snap.isEnabled, let username = snap.username {
            connectedSection(vm: vm, username: username, status: snap.validationStatus)
        } else if let username = snap.username {
            previouslyConnectedSection(vm: vm, username: username)
        } else {
            notConnectedSection(vm: vm)
        }
    }

    private func notConnectedSection(vm: ListenBrainzSettingsViewModel) -> some View {
        @Bindable var vm = vm
        return Section {
            TextField("Username", text: $vm.usernameInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .onChange(of: vm.usernameInput) { _, _ in
                    vm.validateUsernameInputLocally()
                }

            Button {
                Task { await vm.connect() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    if vm.isProcessing {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text("Connect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CassetteColors.accent)
            .disabled(vm.usernameInput.isEmpty || vm.usernameInputValidationError != nil || vm.isProcessing)

            if let error = vm.userFacingError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Connection")
        } footer: {
            if let error = vm.usernameInputValidationError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Enter your ListenBrainz username to enable music recommendations.")
            }
        }
    }

    @ViewBuilder
    private func connectedSection(
        vm: ListenBrainzSettingsViewModel,
        username: String,
        status: ValidationStatus
    ) -> some View {
        Section {
            LabeledContent("Connected as") {
                Text(username).fontWeight(.medium)
            }
            LabeledContent("Status") {
                statusBadge(for: status)
            }
            if case .invalid = status {
                Button {
                    Task { await vm.revalidate() }
                } label: {
                    HStack(spacing: CassetteSpacing.s) {
                        if vm.isProcessing { ProgressView().scaleEffect(0.8) }
                        Text("Retry connection")
                    }
                }
                .disabled(vm.isProcessing)
            }
            if let error = vm.userFacingError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Connection")
        }

        Section {
            Button {
                Task { await vm.disconnect() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    if vm.isProcessing { ProgressView().scaleEffect(0.8) }
                    Text("Disconnect")
                }
            }
            .disabled(vm.isProcessing)

            Button("Forget username", role: .destructive) {
                showForgetAlert = true
            }
        }
        .alert("Forget ListenBrainz Account?", isPresented: $showForgetAlert) {
            Button("Forget", role: .destructive) { Task { await vm.resetCredentials() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your username will be removed. You can reconnect anytime.")
        }
    }

    @ViewBuilder
    private func previouslyConnectedSection(vm: ListenBrainzSettingsViewModel, username: String) -> some View {
        Section {
            LabeledContent("Previously connected as") {
                Text(username).fontWeight(.medium)
            }

            Button {
                vm.usernameInput = username
                Task { await vm.connect() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    if vm.isProcessing { ProgressView().scaleEffect(0.8) }
                    Text("Reconnect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CassetteColors.accent)
            .disabled(vm.isProcessing)

            Button("Forget username", role: .destructive) {
                showForgetAlert = true
            }

            if let error = vm.userFacingError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Connection")
        }
        .alert("Forget ListenBrainz Account?", isPresented: $showForgetAlert) {
            Button("Forget", role: .destructive) { Task { await vm.resetCredentials() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your username will be removed. You can reconnect anytime.")
        }
    }

    // MARK: - Status badge

    private func statusBadge(for status: ValidationStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 8, height: 8)
            Text(statusLabel(for: status))
                .font(.caption)
                .foregroundStyle(statusColor(for: status))
        }
    }

    private func statusColor(for status: ValidationStatus) -> Color {
        switch status {
        case .valid:            .green
        case .validating, .unknown: .orange
        case .invalid:          .red
        }
    }

    private func statusLabel(for status: ValidationStatus) -> String {
        switch status {
        case .valid:      "Connected"
        case .validating: "Validating…"
        case .unknown:    "Validation pending"
        case .invalid:    "Connection issue"
        }
    }
}
