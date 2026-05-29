// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// Result of a /1/validate-token call.
nonisolated struct ListenBrainzValidation: Sendable {
    let isValid: Bool
    /// Username associated with the token, as returned by the server.
    let username: String?
}

/// Immutable snapshot of scrobbling configuration at a given point in time.
/// Separate from ListenBrainzSnapshot (recommendations) — token-based auth vs username-based.
nonisolated struct ScrobblingSnapshot: Sendable, Equatable {
    let isEnabled: Bool
    /// Username returned by /1/validate-token and persisted to Keychain for display on restart.
    let username: String?
    let serverRootURL: String
    let validationStatus: ValidationStatus
}
