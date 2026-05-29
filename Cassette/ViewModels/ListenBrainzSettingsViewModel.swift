// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

nonisolated enum ScrobblingConnectionState: Equatable, Sendable {
    case idle
    case validating
    case connected(username: String?)
    case failed(message: String)
}

@Observable
@MainActor
final class ListenBrainzSettingsViewModel {

    // MARK: - Recommendations state

    var snapshot: ListenBrainzSnapshot = ListenBrainzSnapshot(isEnabled: false, username: nil, validationStatus: .unknown)
    var usernameInput: String = ""
    var isProcessing: Bool = false
    var userFacingError: String?
    var usernameInputValidationError: String?

    // MARK: - Scrobbling state

    var scrobblingSnapshot: ScrobblingSnapshot = ScrobblingSnapshot(
        isEnabled: false,
        username: nil,
        serverRootURL: ListenBrainzService.defaultScrobblingServerURL,
        validationStatus: .unknown
    )
    var isScrobblingToggleOn: Bool = false
    var tokenInput: String = ""
    var serverURLInput: String = ListenBrainzService.defaultScrobblingServerURL
    var scrobblingConnectionState: ScrobblingConnectionState = .idle
    var isScrobblingProcessing: Bool = false

    private let service: ListenBrainzService

    init(service: ListenBrainzService) {
        self.service = service
    }

    // MARK: - Recommendations actions

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

    // MARK: - Scrobbling actions

    func refreshScrobblingSnapshot() async {
        let snap = await service.scrobblingSnapshot()
        scrobblingSnapshot = snap
        serverURLInput = snap.serverRootURL
        isScrobblingToggleOn = snap.isEnabled
        if let username = snap.username {
            scrobblingConnectionState = .connected(username: username)
            isScrobblingToggleOn = snap.isEnabled
        }
    }

    func toggleScrobbling(_ on: Bool) async {
        isScrobblingToggleOn = on
        if on {
            if case .connected = scrobblingConnectionState {
                await service.enableScrobbling()
                scrobblingSnapshot = await service.scrobblingSnapshot()
            }
            // else: form will appear — no UserDefaults write until validated
        } else {
            await service.disableScrobbling()
            scrobblingSnapshot = await service.scrobblingSnapshot()
        }
    }

    func validateScrobblingToken() async {
        guard !tokenInput.isEmpty, !isScrobblingProcessing else { return }
        isScrobblingProcessing = true
        scrobblingConnectionState = .validating
        defer { isScrobblingProcessing = false }

        let rawURL = serverURLInput.isEmpty ? ListenBrainzService.defaultScrobblingServerURL : serverURLInput
        let normalized = ListenBrainzService.normalizeServerURL(rawURL)
        guard let url = URL(string: normalized), url.scheme != nil else {
            scrobblingConnectionState = .failed(message: "Invalid server URL. Use a full URL, e.g. https://api.listenbrainz.org")
            return
        }
        do {
            try await service.validateAndSaveScrobblingToken(tokenInput, rootURL: url)
            let snap = await service.scrobblingSnapshot()
            scrobblingSnapshot = snap
            scrobblingConnectionState = .connected(username: snap.username)
            tokenInput = ""
        } catch let error as ListenBrainzError {
            scrobblingConnectionState = .failed(message: userFacingScrobblingMessage(for: error))
        } catch {
            scrobblingConnectionState = .failed(message: "An unexpected error occurred. Please try again.")
        }
    }

    func startTokenReplacement() {
        scrobblingConnectionState = .idle
        tokenInput = ""
        isScrobblingToggleOn = true
    }

    func disableScrobbling() async {
        await service.disableScrobbling()
        scrobblingSnapshot = await service.scrobblingSnapshot()
        isScrobblingToggleOn = false
    }

    func resetScrobblingToken() async {
        isScrobblingProcessing = true
        defer { isScrobblingProcessing = false }
        await service.clearScrobblingToken()
        scrobblingSnapshot = await service.scrobblingSnapshot()
        scrobblingConnectionState = .idle
        tokenInput = ""
        serverURLInput = ListenBrainzService.defaultScrobblingServerURL
        isScrobblingToggleOn = false
    }

    // MARK: - Error mapping (recommendations)

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

    // MARK: - Error mapping (scrobbling)

    private func userFacingScrobblingMessage(for error: ListenBrainzError) -> String {
        switch error {
        case .unauthorized:
            return "Token is invalid or has been revoked. Check your ListenBrainz account settings."
        case .network:
            return "Couldn't reach the server. Check your connection and URL."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please try again in \(Int(seconds)) seconds."
            }
            return "Too many requests. Please try again in a moment."
        case .httpError(let code):
            return "Server returned an unexpected error (\(code))."
        case .decoding:
            return "Couldn't parse the server response."
        default:
            return "Validation failed. Please check the token and URL."
        }
    }
}
