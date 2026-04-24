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
