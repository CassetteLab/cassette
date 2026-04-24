// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

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
    /// Header name contains characters outside the RFC 7230 tchar set.
    case invalidHeaderName(key: String)
    /// Header value contains \r, \n, or \0 — would enable header-splitting attacks.
    case invalidHeaderValue(key: String)
    case serverNotFound(id: UUID)
    case notImplemented
    /// Requested media is not downloaded and device is offline.
    case offlineUnavailable(songId: String)
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
        case .invalidHeaderName(let key):
            return "Header name '\(key)' contains characters not allowed by RFC 7230."
        case .invalidHeaderValue(let key):
            return "Header '\(key)' value contains invalid characters (\\r, \\n, or \\0 are not allowed)."
        case .serverNotFound(let id):
            return "No server found with ID \(id.uuidString)."
        case .notImplemented:
            return "This feature is not yet implemented."
        case .offlineUnavailable(let id):
            return "'\(id)' is not downloaded and device is offline."
        }
    }
}
