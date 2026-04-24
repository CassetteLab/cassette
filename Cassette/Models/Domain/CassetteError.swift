import Foundation

nonisolated enum CassetteError: Error, Sendable {
    case serverNotConfigured
    case connectionFailed(underlying: any Error & Sendable)
    case mediaNotFound(songId: String)
    case cacheStorageFailed(underlying: any Error & Sendable)
    case downloadFailed(songId: String, underlying: any Error & Sendable)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case invalidServerURL(String)
    /// Header value contains \r or \n — would enable header-splitting attacks.
    case invalidHeaderValue(key: String)
    case notImplemented
}

extension CassetteError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "No server configured. Please add a server in Settings."
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .mediaNotFound(let id):
            return "Media not found for song '\(id)'."
        case .cacheStorageFailed(let error):
            return "Cache storage failed: \(error.localizedDescription)"
        case .downloadFailed(_, let error):
            return "Download failed: \(error.localizedDescription)"
        case .keychainReadFailed(let status):
            return "Keychain read failed (OSStatus \(status))."
        case .keychainWriteFailed(let status):
            return "Keychain write failed (OSStatus \(status))."
        case .keychainDeleteFailed(let status):
            return "Keychain delete failed (OSStatus \(status))."
        case .invalidServerURL(let url):
            return "Invalid server URL: \(url)"
        case .invalidHeaderValue(let key):
            return "Header '\(key)' contains invalid characters (\\r or \\n are not allowed)."
        case .notImplemented:
            return "This feature is not yet implemented."
        }
    }
}
