// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

@Observable
@MainActor
final class ListenBrainzSettingsViewModel {
    var snapshot: ListenBrainzSnapshot = ListenBrainzSnapshot(isEnabled: false, username: nil, validationStatus: .unknown)
    var usernameInput: String = ""
    var isProcessing: Bool = false
    var userFacingError: String?
    var usernameInputValidationError: String?

    private let service: ListenBrainzService

    init(service: ListenBrainzService) {
        self.service = service
    }

    func refreshSnapshot() async {
        snapshot = await service.currentSnapshot()
    }

    func validateUsernameInputLocally() {
        guard !usernameInput.isEmpty else {
            usernameInputValidationError = nil
            return
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let isValid = (1...40).contains(usernameInput.count) &&
                      usernameInput.unicodeScalars.allSatisfy { allowed.contains($0) }
        usernameInputValidationError = isValid
            ? nil
            : "Username contains invalid characters. Use letters, numbers, dashes, or underscores."
    }

    func connect() async {
        guard !isProcessing else { return }
        isProcessing = true
        userFacingError = nil
        defer { isProcessing = false }
        do {
            try await service.enable(username: usernameInput)
        } catch let error as ListenBrainzError {
            userFacingError = userFacingMessage(for: error)
        } catch {
            userFacingError = "An unexpected error occurred. Please try again."
        }
        snapshot = await service.currentSnapshot()
    }

    func disconnect() async {
        isProcessing = true
        defer { isProcessing = false }
        await service.disable()
        snapshot = await service.currentSnapshot()
    }

    func revalidate() async {
        guard !isProcessing else { return }
        isProcessing = true
        userFacingError = nil
        defer { isProcessing = false }
        do {
            try await service.revalidate()
        } catch let error as ListenBrainzError {
            userFacingError = userFacingMessage(for: error)
        } catch {
            userFacingError = "An unexpected error occurred. Please try again."
        }
        snapshot = await service.currentSnapshot()
    }

    func resetCredentials() async {
        isProcessing = true
        userFacingError = nil
        usernameInput = ""
        defer { isProcessing = false }
        await service.clearCredentials()
        snapshot = await service.currentSnapshot()
    }

    // MARK: - Error mapping

    private func userFacingMessage(for error: ListenBrainzError) -> String {
        switch error {
        case .invalidUsername:
            return "Username contains invalid characters. Use letters, numbers, dashes, or underscores."
        case .userNotFound:
            return "No ListenBrainz user found with this username."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please try again in \(Int(seconds)) seconds."
            }
            return "Too many requests. Please try again in a moment."
        case .network:
            return "Couldn't reach ListenBrainz. Check your connection and try again."
        case .unauthorized:
            return "Authentication failed."
        case .httpError(let code):
            return "ListenBrainz returned an unexpected error (\(code))."
        case .decoding:
            return "Couldn't parse response from ListenBrainz."
        }
    }
}
