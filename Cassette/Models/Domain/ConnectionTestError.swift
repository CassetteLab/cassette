import Foundation

/// Differentiated errors from a server connection test (ping + getUser).
nonisolated enum ConnectionTestError: Error, Sendable {
    /// The URL string is malformed or missing a scheme/host.
    case invalidURL
    /// A network-level error — server was not reached at all.
    case unreachable
    /// Server was reached but rejected the credentials.
    case authenticationFailed
    /// Server returned an API-level error (not auth-related).
    case serverError(message: String)
    /// An unexpected error not covered by the above cases.
    case unknown(description: String)
}

extension ConnectionTestError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is not valid. Check the format (e.g. https://music.example.com)."
        case .unreachable:
            return "Could not reach the server. Check the URL and your network connection."
        case .authenticationFailed:
            return "Incorrect username or password."
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let description):
            return "Unexpected error: \(description)"
        }
    }
}
