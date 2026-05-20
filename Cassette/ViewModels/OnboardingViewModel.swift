// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    var serverURL: String = ""
    var username: String = ""
    var password: String = ""
    var customHeaders: [CustomHeaderEntry] = []
    var isLoading: Bool = false
    var connectionError: ConnectionTestError?

    /// Display name derived from the URL host, falling back to the raw URL string.
    var derivedDisplayName: String {
        URL(string: serverURL.trimmingCharacters(in: .whitespaces))?.host ?? serverURL
    }

    var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.isEmpty &&
        !password.isEmpty
    }

    var isHTTP: Bool {
        serverURL.lowercased().hasPrefix("http://")
    }

    private let serverService: any ServerServiceProtocol

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    func testConnection() async {
        guard !isLoading else { return }
        connectionError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await serverService.testConnection(
                url: serverURL,
                username: username,
                password: password,
                customHeaders: headersDict()
            )
        } catch let error as ConnectionTestError {
            connectionError = error
        } catch {
            let e = error as NSError
            connectionError = .unknown(domain: e.domain, code: e.code)
        }
    }

    /// Validates, tests, and persists the server in a single flow.
    /// On success state.activeServer becomes non-nil and RootView transitions automatically.
    func addServer() async {
        guard !isLoading else { return }
        connectionError = nil
        isLoading = true
        defer { isLoading = false }

        let trimmedURL = serverURL.trimmingCharacters(in: .whitespaces)
        let headers = headersDict()

        do {
            try await serverService.testConnection(
                url: trimmedURL,
                username: username,
                password: password,
                customHeaders: headers
            )
        } catch let error as ConnectionTestError {
            connectionError = error
            return
        } catch {
            let e = error as NSError
            connectionError = .unknown(domain: e.domain, code: e.code)
            return
        }

        do {
            try await serverService.addServer(
                displayName: derivedDisplayName,
                baseURL: trimmedURL,
                username: username,
                password: password,
                customHeaders: headers
            )
        } catch {
            let e = error as NSError
            connectionError = .unknown(domain: e.domain, code: e.code)
        }
    }

    func addCustomHeader() {
        customHeaders.append(CustomHeaderEntry())
    }

    func removeCustomHeader(id: UUID) {
        customHeaders.removeAll { $0.id == id }
    }

    // MARK: - Private

    var redactedDescription: String {
        "OnboardingViewModel(username: \(username), password: [REDACTED], customHeaders: [REDACTED])"
    }

    private func headersDict() -> [String: String] {
        var dict: [String: String] = [:]
        for pair in customHeaders where !pair.key.isEmpty {
            dict[pair.key] = pair.value
        }
        return dict
    }
}
