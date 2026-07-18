// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum UserFacingError: LocalizedError, Identifiable, Sendable {
    case noNetwork
    case serverUnreachable
    case authenticationFailed
    case contentUnavailableOffline
    case downloadFailed
    case playbackFailed
    case syncFailed
    case unexpected

    var id: String {
        switch self {
        case .noNetwork: "noNetwork"
        case .serverUnreachable: "serverUnreachable"
        case .authenticationFailed: "authenticationFailed"
        case .contentUnavailableOffline: "contentUnavailableOffline"
        case .downloadFailed: "downloadFailed"
        case .playbackFailed: "playbackFailed"
        case .syncFailed: "syncFailed"
        case .unexpected: "unexpected"
        }
    }

    var errorDescription: String? {
        switch self {
        case .noNetwork: String(localized: "No internet connection.")
        case .serverUnreachable: String(localized: "Couldn't reach your server.")
        case .authenticationFailed: String(localized: "Authentication failed.")
        case .contentUnavailableOffline: String(localized: "This content isn't available offline.")
        case .downloadFailed: String(localized: "Download failed.")
        case .playbackFailed: String(localized: "Couldn't play this track.")
        case .syncFailed: String(localized: "Couldn't sync with your server.")
        case .unexpected: String(localized: "Something went wrong.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noNetwork: String(localized: "Check your connection and try again.")
        case .serverUnreachable: String(localized: "Make sure your server is running and reachable.")
        case .authenticationFailed: String(localized: "Verify your credentials in Settings.")
        case .contentUnavailableOffline: String(localized: "Download this content first, or reconnect to your server.")
        case .downloadFailed: String(localized: "Check your connection and storage, then try again.")
        case .playbackFailed: String(localized: "Try again or skip to another track.")
        case .syncFailed: String(localized: "Your changes are saved and will sync when your server is reachable.")
        case .unexpected: nil
        }
    }

    var displayMessage: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }

    static func from(_ error: any Error) -> UserFacingError {
        if error is CancellationError { return .unexpected }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .noNetwork
            case .userAuthenticationRequired:
                return .authenticationFailed
            default:
                return .serverUnreachable
            }
        }
        if let cassetteError = error as? CassetteError {
            switch cassetteError {
            case .offlineUnavailable:
                return .contentUnavailableOffline
            case .downloadFailed:
                return .downloadFailed
            case .connectionFailed, .serverNotConfigured, .serverNotFound:
                return .serverUnreachable
            default:
                return .unexpected
            }
        }
        return .unexpected
    }
}
