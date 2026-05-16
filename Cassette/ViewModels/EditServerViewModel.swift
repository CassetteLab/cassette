// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

@Observable
@MainActor
final class EditServerViewModel {
    var serverURL: String
    var username: String
    var password: String = ""
    var customHeaders: [(key: String, value: String)] = []

    var isSaving: Bool = false
    var isLoadingCredentials: Bool = true
    var connectionError: ConnectionTestError?
    var saveError: String?

    var hasUnsavedChanges: Bool {
        serverURL != initialURL ||
        username != initialUsername ||
        password != initialPassword ||
        !headersMatch(customHeaders, initialHeaders)
    }

    var canSave: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.isEmpty &&
        !password.isEmpty
    }

    private let serverId: UUID
    private var initialURL: String
    private var initialUsername: String
    private var initialPassword: String = ""
    private var initialHeaders: [(key: String, value: String)] = []

    private let serverService: any ServerServiceProtocol

    init(server: ServerSnapshot, serverService: any ServerServiceProtocol) {
        self.serverId = server.id
        self.serverURL = server.baseURL
        self.username = server.username
        self.initialURL = server.baseURL
        self.initialUsername = server.username
        self.serverService = serverService
    }

    func loadCredentials() async {
        isLoadingCredentials = true
        defer { isLoadingCredentials = false }
        do {
            let creds = try await serverService.activeCredentials()
            password = creds.password
            initialPassword = creds.password
            let pairs = creds.customHeaders
                .sorted { $0.key < $1.key }
                .map { (key: $0.key, value: $0.value) }
            customHeaders = pairs
            initialHeaders = pairs
        } catch {
            saveError = error.localizedDescription
        }
    }

    func save() async {
        guard !isSaving else { return }
        connectionError = nil
        saveError = nil
        isSaving = true
        defer { isSaving = false }

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
            connectionError = .unknown(description: error.localizedDescription)
            return
        }

        let derivedName = URL(string: trimmedURL)?.host ?? trimmedURL
        do {
            try await serverService.updateServer(
                id: serverId,
                displayName: derivedName,
                baseURL: trimmedURL,
                username: username,
                password: password,
                customHeaders: headers
            )
            initialURL = trimmedURL
            initialUsername = username
            initialPassword = password
            initialHeaders = customHeaders
        } catch {
            saveError = error.localizedDescription
        }
    }

    func addCustomHeader() {
        customHeaders.append((key: "", value: ""))
    }

    func removeCustomHeader(at index: Int) {
        guard customHeaders.indices.contains(index) else { return }
        customHeaders.remove(at: index)
    }

    // MARK: - Private

    private func headersDict() -> [String: String] {
        var dict: [String: String] = [:]
        for pair in customHeaders where !pair.key.isEmpty {
            dict[pair.key] = pair.value
        }
        return dict
    }

    private func headersMatch(
        _ lhs: [(key: String, value: String)],
        _ rhs: [(key: String, value: String)]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}
