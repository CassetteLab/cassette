// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    /// Smart Shuffle returned no eligible tracks (library too small or no downloads offline).
    case smartShuffleEmpty
    /// Instant Mix returned no similar tracks (server has no similarity data / plugin unavailable).
    case instantMixEmpty
    /// All album fetches failed while building the artist's full track list.
    case artistTracksUnavailable
    /// An operation exceeded its allowed time budget and was cancelled.
    case timeout
}

extension CassetteError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return String(localized: "No server configured. Please add a server in Settings.")
        case .connectionFailed(let error):
            return String(localized: "Connection failed: \(error.localizedDescription)")
        case .mediaNotFound(let id):
            return String(localized: "Media not found for song '\(id)'.")
        case .cacheStorageFailed(let error):
            return String(localized: "Cache storage failed: \(error.localizedDescription)")
        case .downloadFailed(_, let error):
            return String(localized: "Download failed: \(error.localizedDescription)")
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
            return String(localized: "This feature is not yet implemented.")
        case .offlineUnavailable(let id):
            return String(localized: "'\(id)' is not downloaded and device is offline.")
        case .smartShuffleEmpty:
            return String(localized: "Your library is too small for Smart Shuffle. Try downloading more music or playing some tracks first.")
        case .instantMixEmpty:
            return String(localized: "No similar tracks found for an Instant Mix. Your server may not have similarity data for this yet.")
        case .artistTracksUnavailable:
            return String(localized: "Unable to load tracks for this artist. Please check your connection and try again.")
        case .timeout:
            return String(localized: "The operation timed out. Please check your connection and try again.")
        }
    }
}
