// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum ListenBrainzError: Error, Sendable {
    case invalidUsername
    case userNotFound
    case network(any Error)
    case decoding(any Error)
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(statusCode: Int)
    case unauthorized
}

extension ListenBrainzError: LocalizedError {
    /// Generic descriptions — username and internal details are never included.
    nonisolated var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return String(localized: "The username format is not valid.")
        case .userNotFound:
            return String(localized: "This account does not exist on ListenBrainz.")
        case .network:
            return String(localized: "A network error occurred. Please check your connection and try again.")
        case .decoding:
            return String(localized: "Unable to parse the server response.")
        case .rateLimited(let retryAfter):
            if let delay = retryAfter {
                return String(localized: "Too many requests. Please wait \(Int(delay)) seconds before trying again.")
            }
            return String(localized: "Too many requests. Please wait before trying again.")
        case .httpError(let code):
            return String(localized: "The server returned an unexpected error (HTTP \(code)).")
        case .unauthorized:
            return String(localized: "Authentication failed.")
        }
    }
}

// Override description and debugDescription to prevent username leaking
// through default error printing in logs or crash reporters.
extension ListenBrainzError: CustomStringConvertible {
    nonisolated var description: String { errorDescription ?? "ListenBrainz error" }
}

extension ListenBrainzError: CustomDebugStringConvertible {
    nonisolated var debugDescription: String { errorDescription ?? "ListenBrainz error" }
}

extension ListenBrainzError {
    nonisolated var isTransient: Bool {
        switch self {
        case .network, .rateLimited: return true
        case .httpError(let code) where (500...599).contains(code): return true
        default: return false
        }
    }

    nonisolated var isAuthenticationFailure: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// Suggested seconds to wait before retrying. `nil` means no retry is appropriate.
    nonisolated var suggestedRetryDelay: TimeInterval? {
        switch self {
        case .rateLimited(let after): return after ?? 60
        case .network: return 5
        default: return nil
        }
    }
}
