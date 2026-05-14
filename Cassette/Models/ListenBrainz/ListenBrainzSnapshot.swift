// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum ValidationStatus: Sendable, Equatable {
    case unknown
    case validating
    case valid
    case invalid(reason: String)
}

/// Immutable snapshot of ListenBrainzService state at a given point in time.
/// Safe to pass across actor boundaries.
nonisolated struct ListenBrainzSnapshot: Sendable, Equatable {
    let isEnabled: Bool
    let username: String?
    let validationStatus: ValidationStatus
}
