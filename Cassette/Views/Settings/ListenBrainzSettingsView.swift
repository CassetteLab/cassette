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
    @State private var showForgetScrobblingAlert = false

    var body: some View {
        Group {
            if let vm = viewModel {
                Form {
                    aboutSection()
                    connectionSection(vm: vm)
                    scrobblingToggleSection(vm: vm)
                    scrobblingConfigSection(vm: vm)
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
            await viewModel?.refreshScrobblingSnapshot()
        }
    }

    // MARK: - About

    private func aboutSection() -> some View {
        Section {
            Text("ListenBrainz is an open-source music scrobbling and recommendation service by the MetaBrainz Foundation. Cassette can submit your listening history and surface personalized fresh releases and similar artists.")
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

    // MARK: - Recommendations connection

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
            Text("Recommendations Account")
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
            Text("Recommendations Account")
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
            Text("Recommendations Account")
        }
        .alert("Forget ListenBrainz Account?", isPresented: $showForgetAlert) {
            Button("Forget", role: .destructive) { Task { await vm.resetCredentials() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your username will be removed. You can reconnect anytime.")
        }
    }

    // MARK: - Scrobbling

    private func scrobblingToggleSection(vm: ListenBrainzSettingsViewModel) -> some View {
        Section {
            Toggle(
                "Submit listens to ListenBrainz",
                isOn: Binding(
                    get: { vm.isScrobblingToggleOn },
                    set: { on in Task { await vm.toggleScrobbling(on) } }
                )
            )
        } header: {
            Text("Scrobbling")
        } footer: {
            Text("If your server already relays listens to ListenBrainz, leave this disabled to avoid duplicate scrobbles.")
        }
    }

    @ViewBuilder
    private func scrobblingConfigSection(vm: ListenBrainzSettingsViewModel) -> some View {
        if case .connected(let username) = vm.scrobblingConnectionState {
            scrobblingConnectedSection(vm: vm, username: username)
        } else if vm.isScrobblingToggleOn {
            scrobblingInputSection(vm: vm)
        }
    }

    private func scrobblingInputSection(vm: ListenBrainzSettingsViewModel) -> some View {
        @Bindable var vm = vm
        return Section {
            SecureField("User token", text: $vm.tokenInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .textContentType(.password)
                #endif

            TextField("Server URL", text: $vm.serverURLInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif

            Button {
                Task { await vm.validateScrobblingToken() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    if case .validating = vm.scrobblingConnectionState {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text("Validate")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CassetteColors.accent)
            .disabled(vm.tokenInput.isEmpty || vm.isScrobblingProcessing)

            if case .failed(let message) = vm.scrobblingConnectionState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Token")
        } footer: {
            Text("Find your user token at listenbrainz.org → Profile → Music Services & API.")
        }
    }

    @ViewBuilder
    private func scrobblingConnectedSection(vm: ListenBrainzSettingsViewModel, username: String?) -> some View {
        Section {
            LabeledContent("Connected as") {
                Text(username ?? "ListenBrainz").fontWeight(.medium)
            }
            LabeledContent("Scrobbling") {
                Text(vm.scrobblingSnapshot.isEnabled ? "Active" : "Paused")
                    .foregroundStyle(vm.scrobblingSnapshot.isEnabled ? .green : .secondary)
            }
            Button("Replace token") {
                vm.startTokenReplacement()
            }
        } header: {
            Text("Token")
        }

        Section {
            Button("Forget credentials", role: .destructive) {
                showForgetScrobblingAlert = true
            }
            .disabled(vm.isScrobblingProcessing)
        }
        .alert("Forget Scrobbling Credentials?", isPresented: $showForgetScrobblingAlert) {
            Button("Forget", role: .destructive) { Task { await vm.resetScrobblingToken() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your token will be removed and scrobbling disabled. You can reconnect anytime.")
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
