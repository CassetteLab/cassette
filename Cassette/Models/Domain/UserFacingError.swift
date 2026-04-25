// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
        case .noNetwork: "No internet connection."
        case .serverUnreachable: "Couldn't reach your server."
        case .authenticationFailed: "Authentication failed."
        case .contentUnavailableOffline: "This content isn't available offline."
        case .downloadFailed: "Download failed."
        case .playbackFailed: "Couldn't play this track."
        case .syncFailed: "Couldn't sync with your server."
        case .unexpected: "Something went wrong."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noNetwork: "Check your connection and try again."
        case .serverUnreachable: "Make sure your server is running and reachable."
        case .authenticationFailed: "Verify your credentials in Settings."
        case .contentUnavailableOffline: "Download this content first, or reconnect to your server."
        case .downloadFailed: "Check your connection and storage, then try again."
        case .playbackFailed: "Try again or skip to another track."
        case .syncFailed: "Your changes are saved and will sync when your server is reachable."
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
