// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ServerFormView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        Form {
            Section("Server") {
                TextField("https://music.example.com", text: $viewModel.serverURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                urlInlineError
                httpWarning
            }

            Section("Credentials") {
                TextField("Username", text: $viewModel.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $viewModel.password)
                credentialsInlineError
            }

            generalError

            customHeadersSection

            Section {
                Button {
                    Task { await viewModel.addServer() }
                } label: {
                    if viewModel.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Connecting…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect & Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isLoading || !viewModel.canSubmit)
            }
        }
        .navigationTitle("Add Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Inline error helpers

    @ViewBuilder
    private var httpWarning: some View {
        if viewModel.isHTTP {
            Label("Unencrypted connection — make sure you are on a trusted network.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var urlInlineError: some View {
        if let error = viewModel.connectionError {
            switch error {
            case .invalidURL:
                inlineError("Enter a valid URL (e.g. https://music.example.com).")
            case .unreachable:
                inlineError("Could not reach this server. Check the URL and your network.")
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var credentialsInlineError: some View {
        if case .authenticationFailed = viewModel.connectionError {
            inlineError("Incorrect username or password.")
        }
    }

    @ViewBuilder
    private var generalError: some View {
        if let error = viewModel.connectionError {
            switch error {
            case .serverError, .unknown:
                Section {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            default:
                EmptyView()
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

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

// MARK: - CustomHeaderRowView

struct CustomHeaderRowView: View {
    @Binding var key: String
    @Binding var value: String
    let onRemove: () -> Void

    @State private var isRevealed: Bool = false
    @State private var justCopied: Bool = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            TextField("Name", text: $key)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            HStack(spacing: 0) {
                valueField
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(isRevealed ? CassetteColors.accent : CassetteColors.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isRevealed)

                Button {
                    copyValueToClipboard()
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(value.isEmpty ? CassetteColors.textTertiary : CassetteColors.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(value.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: justCopied)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            if !key.isEmpty && !HeaderValidator.isValidName(key) {
                Text("Name '\(key)' contains characters not allowed by RFC 7230.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !value.isEmpty && !HeaderValidator.isValidValue(value) {
                Text("Value contains CR, LF, or NUL — not allowed in HTTP headers.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, CassetteSpacing.xs)
        .onDisappear {
            isRevealed = false
            copyFeedbackTask?.cancel()
        }
    }

    @ViewBuilder
    private var valueField: some View {
        if isRevealed {
            TextField("Value", text: $value)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } else {
            SecureField("Value", text: $value)
        }
    }

    private func copyValueToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif

        copyFeedbackTask?.cancel()
        justCopied = true
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            justCopied = false
        }
    }
}
