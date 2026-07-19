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
    /// API token for this server's AudioMuse-AI instance, sent as `Authorization: Bearer`.
    /// Optional in both senses: AudioMuse may not be configured at all, and an instance running
    /// with `AUTH_ENABLED=false` accepts requests without any token.
    let audioMuseToken: String?

    init(password: String, customHeaders: [String: String], audioMuseToken: String? = nil) {
        self.password = password
        self.customHeaders = customHeaders
        self.audioMuseToken = audioMuseToken
    }

    static func keychainKey(for serverId: UUID) -> String {
        "cassette.server.\(serverId.uuidString)"
    }
}

extension ServerCredentials: CustomStringConvertible {
    var description: String { "ServerCredentials(password: [REDACTED], customHeaders: [REDACTED], audioMuseToken: [REDACTED])" }
}

extension ServerCredentials: CustomDebugStringConvertible {
    var debugDescription: String { "ServerCredentials(password: [REDACTED], customHeaders: [REDACTED], audioMuseToken: [REDACTED])" }
}
