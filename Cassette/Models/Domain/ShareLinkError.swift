// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// Why a public share link could not be created.
///
/// Sharing is part of the Subsonic spec, but servers differ: Navidrome ships it enabled,
/// others expose no such endpoint at all, and an admin can turn it off. There is no
/// capability flag to read, so the attempt itself is the probe and this type turns what
/// comes back into something worth showing a person. The mapping is pure, so the message
/// is testable without a server.
nonisolated enum ShareLinkError: Error, Sendable, Equatable {
    /// The server has sharing switched off, or is too old to know the endpoint.
    case sharingUnavailable
    /// The server knows the endpoint but refuses it for this account.
    case notPermitted
    /// The server could not be reached, or answered too slowly.
    case unreachable
    /// Anything else — the detail belongs in the log, not in front of the user.
    case other

    init(_ error: any Error) {
        if let shareError = error as? ShareLinkError {
            self = shareError
            return
        }
        guard let swiftSonicError = error as? SwiftSonicError else {
            self = error is URLError ? .unreachable : .other
            return
        }
        switch swiftSonicError {
        case .api(let apiError):
            switch apiError.code {
            case .notFound, .generic, .missingParameter, .clientMustUpgrade, .serverMustUpgrade:
                // Navidrome answers a disabled feature with a generic failure, and a server
                // without the endpoint answers "not found". Both mean the same thing here.
                self = .sharingUnavailable
            case .unauthorized, .trialExpired, .wrongCredentials, .invalidAPIKey,
                 .tokenAuthNotSupportedForLDAP, .authMechanismNotSupported, .conflictingAuthMechanisms:
                self = .notPermitted
            default:
                // `.unknown` today, and whatever code SwiftSonic learns next: not something
                // we can phrase usefully for a person.
                self = .other
            }
        case .network, .rateLimited, .httpError:
            self = .unreachable
        case .decoding, .invalidConfiguration, .insecureRedirect:
            self = .other
        }
    }

    /// What the toast says. Deliberately actionable: "turned off" and "not allowed" send the
    /// user to two different places.
    var userMessage: String {
        switch self {
        case .sharingUnavailable:
            return String(localized: "Your server has sharing turned off.")
        case .notPermitted:
            return String(localized: "Your account is not allowed to create share links.")
        case .unreachable:
            return String(localized: "Could not reach your server.")
        case .other:
            return String(localized: "Could not create a share link.")
        }
    }
}
