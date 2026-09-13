// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

/// Sendable value-type snapshot of a ServerConfig for crossing actor boundaries safely.
nonisolated struct ServerSnapshot: Sendable, Equatable {
    let id: UUID
    let displayName: String
    let baseURL: String
    let username: String
    let serverVersion: String?
    /// Base URL of this server's AudioMuse-AI instance, or nil when none is configured.
    /// Mirrored here so views can show or hide the mood features without a SwiftData fetch.
    let audioMuseURL: String?
    /// The library browsing is scoped to, or nil for all of them. Mirrored here so views and the
    /// library service can read the scope without a SwiftData fetch.
    let selectedMusicFolderId: String?
    /// Encoded set of playlist kinds hidden from the playlist list. Mirrored here so the list and
    /// its toolbar read the filter without a SwiftData fetch, like the scope above.
    let hiddenPlaylistKinds: String?

    /// The filter in usable form. Decoded on read rather than stored so the snapshot stays a plain
    /// mirror of the persisted column.
    var hiddenPlaylistKindSet: Set<PlaylistKind> { PlaylistKind.decodeHidden(hiddenPlaylistKinds) }

    init(from config: ServerConfig) {
        self.id = config.id
        self.displayName = config.displayName
        self.baseURL = config.baseURL
        self.username = config.username
        self.serverVersion = config.serverVersion
        self.audioMuseURL = config.audioMuseURL
        self.selectedMusicFolderId = config.selectedMusicFolderId
        self.hiddenPlaylistKinds = config.hiddenPlaylistKinds
    }
}

/// Identity for `.task(id:)` on the library views: they reload when connectivity flips, and now
/// also when the user scopes browsing to a different library. Bundling both keeps each view to a
/// single task rather than a task plus a change handler.
nonisolated struct LibraryLoadKey: Hashable, Sendable {
    let isOnline: Bool
    let musicFolderId: String?
}

/// Observable UI state for server connectivity. Updated by ServerService via MainActor.run.
@Observable
@MainActor
final class ServerState {
    var servers: [ServerSnapshot] = []
    var activeServer: ServerSnapshot?
    var isConnected: Bool = false
    /// Updated by NetworkMonitor. False when NWPathMonitor reports no connectivity.
    var isOnline: Bool = true

    /// See ``LibraryLoadKey``.
    var libraryLoadKey: LibraryLoadKey {
        LibraryLoadKey(isOnline: isOnline, musicFolderId: activeServer?.selectedMusicFolderId)
    }
    /// Updated by NetworkMonitor. True when the connection is metered (cellular, hotspot).
    /// Default false — optimistic until the first NWPath update corrects it on launch (~100ms).
    var isExpensive: Bool = false
    // Prevents OnboardingView flash before persisted state is restored on launch.
    var isLoadingPersistedState: Bool = true
}
