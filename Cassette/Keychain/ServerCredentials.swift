// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

// IMPORTANT: Never persist outside of Keychain.
nonisolated struct ServerCredentials: Codable, Sendable {
    let password: String
    /// Custom HTTP headers injected on all requests (e.g. Cloudflare Access tokens).
    /// Treated as secrets — never logged, never stored outside Keychain.
    let customHeaders: [String: String]

    static func keychainKey(for serverId: UUID) -> String {
        "cassette.server.\(serverId.uuidString)"
    }
}
