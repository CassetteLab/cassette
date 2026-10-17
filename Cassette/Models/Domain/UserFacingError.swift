// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

nonisolated enum UserFacingError: LocalizedError, Identifiable, Sendable {
    case noNetwork
    case serverUnreachable
    case authenticationFailed
    case contentUnavailableOffline
    case downloadFailed
    case playbackFailed
    case syncFailed
    /// The server answered, and said it cannot do this. Retrying changes nothing.
    case notSupportedByServer
    case notFound
    case notAuthorized
    case trialExpired
    /// The server answered something Cassette could not read as Subsonic at all.
    case incompatibleServer
    case rateLimited
    /// The server reached the request and failed on its own side — its problem, possibly temporary.
    case serverError
    case insecureRedirect
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
        case .notSupportedByServer: "notSupportedByServer"
        case .notFound: "notFound"
        case .notAuthorized: "notAuthorized"
        case .trialExpired: "trialExpired"
        case .incompatibleServer: "incompatibleServer"
        case .rateLimited: "rateLimited"
        case .serverError: "serverError"
        case .insecureRedirect: "insecureRedirect"
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
        case .notSupportedByServer: String(localized: "Your server doesn't support this.")
        case .notFound: String(localized: "This isn't on your server anymore.")
        case .notAuthorized: String(localized: "Your account isn't allowed to do this.")
        case .trialExpired: String(localized: "Your server's trial period has ended.")
        case .incompatibleServer: String(localized: "Your server replied with something Cassette couldn't read.")
        case .rateLimited: String(localized: "Your server is asking Cassette to slow down.")
        case .serverError: String(localized: "Your server ran into an error.")
        case .insecureRedirect: String(localized: "Your server redirected to another address.")
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
        case .notSupportedByServer: String(localized: "Not every Subsonic server implements every feature. The rest of your library still works.")
        case .notFound: nil
        case .notAuthorized: String(localized: "Ask whoever runs the server to check your permissions.")
        case .trialExpired: String(localized: "Contact whoever runs the server.")
        case .incompatibleServer: String(localized: "It may not be a Subsonic server, or it may implement only part of the API.")
        case .rateLimited: String(localized: "Wait a moment and try again.")
        case .serverError: String(localized: "Check your server's logs, then try again.")
        case .insecureRedirect: String(localized: "Cassette blocked it. Check your reverse proxy configuration.")
        case .unexpected: nil
        }
    }

    var displayMessage: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }

    /// Whether running the same request again could plausibly succeed.
    ///
    /// A Retry button on an error that cannot change is a promise the app can't keep: the user
    /// taps it, the same request fails the same way, and nothing explains why. These are the
    /// errors where the server has already given its answer — only the user, or the server's
    /// owner, can change it.
    var isRetryable: Bool {
        switch self {
        case .noNetwork, .serverUnreachable, .downloadFailed, .playbackFailed,
             .syncFailed, .rateLimited, .serverError, .unexpected:
            return true
        case .authenticationFailed, .contentUnavailableOffline, .notSupportedByServer,
             .notFound, .notAuthorized, .trialExpired, .incompatibleServer, .insecureRedirect:
            return false
        }
    }

    static func from(_ error: any Error) -> UserFacingError {
        if error is CancellationError { return .unexpected }
        if let sonic = error as? SwiftSonicError { return from(sonic) }
        if let urlError = error as? URLError { return from(urlError) }
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

    /// Every error SwiftSonic can throw used to land here as `.unexpected` — "Something went
    /// wrong", beside a Retry button that replayed the same failing request. A server that
    /// answers "I don't implement that" deserves to be quoted, not paraphrased into nothing.
    private static func from(_ error: SwiftSonicError) -> UserFacingError {
        switch error {
        case .api(let apiError):
            switch apiError.code {
            case .wrongCredentials, .invalidAPIKey, .tokenAuthNotSupportedForLDAP,
                 .authMechanismNotSupported, .conflictingAuthMechanisms:
                return .authenticationFailed
            case .unauthorized:
                return .notAuthorized
            case .trialExpired:
                return .trialExpired
            case .notFound:
                return .notFound
            case .serverMustUpgrade:
                return .notSupportedByServer
            // The server rejected the request itself rather than what it asked for: either it
            // wants a parameter the spec doesn't require, or it speaks a dialect Cassette doesn't.
            case .clientMustUpgrade, .missingParameter:
                return .incompatibleServer
            case .generic, .unknown:
                return .serverError
            }
        case .network(let urlError):
            return from(urlError)
        // A 2xx that isn't Subsonic JSON. A partial implementation answering HTML or an empty
        // body lands here, which is the honest reading: the server replied, just not in Subsonic.
        case .decoding:
            return .incompatibleServer
        case .httpError(let statusCode, _, _):
            switch statusCode {
            case 401, 403: return .authenticationFailed
            case 404, 501: return .notSupportedByServer
            default: return .serverError
            }
        case .rateLimited:
            return .rateLimited
        case .invalidConfiguration:
            return .serverUnreachable
        case .insecureRedirect:
            return .insecureRedirect
        }
    }

    private static func from(_ error: URLError) -> UserFacingError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noNetwork
        case .userAuthenticationRequired:
            return .authenticationFailed
        default:
            return .serverUnreachable
        }
    }
}
