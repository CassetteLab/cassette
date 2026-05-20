// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct EditServerView: View {
    @Bindable var viewModel: EditServerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardAlert = false
    @State private var isPasswordRevealed = false

    var body: some View {
        Group {
            if viewModel.isLoadingCredentials {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form
            }
        }
        .navigationTitle("Server Configuration")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.hasUnsavedChanges)
        #endif
        .toolbar { toolbar }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .task {
            await viewModel.loadCredentials()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(iOS)
        if viewModel.hasUnsavedChanges {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showDiscardAlert = true
                } label: {
                    Image(systemName: "chevron.backward")
                        .fontWeight(.semibold)
                }
            }
        }
        #endif
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isSaving {
                ProgressView()
            } else {
                Button("Save") {
                    Task {
                        await viewModel.save()
                        if viewModel.connectionError == nil,
                           viewModel.saveError == nil,
                           !viewModel.hasUnsavedChanges {
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.canSave)
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            serverSection
            credentialsSection
            errorSection
            customHeadersSection
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var serverSection: some View {
        Section("Server") {
            TextField("https://music.example.com", text: $viewModel.serverURL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            invalidURLHint
            httpWarning
        }
    }

    private var credentialsSection: some View {
        Section("Credentials") {
            TextField("Username", text: $viewModel.username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            HStack(spacing: 8) {
                passwordField
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isPasswordRevealed.toggle()
                } label: {
                    Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        if isPasswordRevealed {
            TextField("Password", text: $viewModel.password)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } else {
            SecureField("Password", text: $viewModel.password)
        }
    }

    @ViewBuilder
    private var httpWarning: some View {
        if viewModel.isHTTP {
            Label("Unencrypted connection — make sure you are on a trusted network.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var invalidURLHint: some View {
        if case .invalidURL = viewModel.connectionError {
            Text("Enter a valid URL, including http:// or https://")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.connectionError, error != .invalidURL {
            Section {
                ConnectionErrorView(error: error)
                    .padding(.vertical, CassetteSpacing.xs)
            }
        }
        if let error = viewModel.saveError {
            Section {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var customHeadersSection: some View {
        Section {
            DisclosureGroup("Custom Headers") {
                ForEach(viewModel.customHeaders.indices, id: \.self) { index in
                    CustomHeaderRowView(
                        key: Binding(
                            get: { viewModel.customHeaders[index].key },
                            set: { viewModel.customHeaders[index].key = $0 }
                        ),
                        value: Binding(
                            get: { viewModel.customHeaders[index].value },
                            set: { viewModel.customHeaders[index].value = $0 }
                        ),
                        onRemove: { viewModel.removeCustomHeader(at: index) }
                    )
                }
                Button(action: viewModel.addCustomHeader) {
                    Label("Add Header", systemImage: "plus")
                }
            }
        } footer: {
            Text("Optional headers sent with every request — useful for Cloudflare Access or other reverse-proxy authentication.")
                .font(.footnote)
        }
    }

}

// MARK: - Navigation destination wrapper

/// Owns the ViewModel lifetime so it is created exactly once per navigation push.
struct EditServerDestinationView: View {
    let server: ServerSnapshot
    let serverService: any ServerServiceProtocol
    @State private var viewModel: EditServerViewModel

    init(server: ServerSnapshot, serverService: any ServerServiceProtocol) {
        self.server = server
        self.serverService = serverService
        self._viewModel = State(initialValue: EditServerViewModel(server: server, serverService: serverService))
    }

    var body: some View {
        EditServerView(viewModel: viewModel)
    }
}
