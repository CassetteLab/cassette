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

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
