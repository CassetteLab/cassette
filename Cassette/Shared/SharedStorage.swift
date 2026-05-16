// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum SharedStorage {
    static let appGroupID = "group.fr.mathieu-dubart.Cassette"

    /// UserDefaults shared between app and widget extension.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// File container shared between app and widget extension.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Subdirectory for cover art cache inside the App Group container.
    static var coverArtCacheDirectory: URL? {
        containerURL?.appendingPathComponent("CoverArt", isDirectory: true)
    }

    static func ensureDirectoriesExist() throws {
        guard let coverDir = coverArtCacheDirectory else { return }
        try FileManager.default.createDirectory(at: coverDir, withIntermediateDirectories: true)
    }
}

nonisolated enum SharedStorageKey: String {
    case recentlyPlayedItems
    case pinnedItems
    case dominantColors
    case nowPlayingState
}

/// Stable cross-process DTO for a recently played track.
/// Never rename fields — UserDefaults persists JSON between app and widget processes.
nonisolated struct SharedTrackInfo: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumID: String?
    /// Filename relative to SharedStorage.coverArtCacheDirectory, nil if not cached yet.
    let coverArtFilename: String?
}

/// Stable cross-process DTO for a pinned item.
/// Never rename fields — UserDefaults persists JSON between app and widget processes.
nonisolated struct SharedPinnedItem: Codable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case album, playlist
    }

    let id: String
    let kind: Kind
    let title: String
    /// Artist for album, track count for playlist.
    let subtitle: String?
    /// Filename relative to SharedStorage.coverArtCacheDirectory, nil if not cached yet.
    let coverArtFilename: String?
}
