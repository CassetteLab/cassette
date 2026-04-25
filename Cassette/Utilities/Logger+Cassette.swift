// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import OSLog

// All properties are `nonisolated` to prevent SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor
// from implicitly isolating them, which would cause concurrency warnings when accessed
// from non-MainActor contexts (actors, background tasks, etc.). Logger is Sendable.
extension Logger {
    nonisolated static let server     = Logger(subsystem: "app.cassette.server",     category: "ServerService")
    nonisolated static let player     = Logger(subsystem: "app.cassette.player",     category: "PlayerService")
    nonisolated static let library    = Logger(subsystem: "app.cassette.library",    category: "LibraryService")
    nonisolated static let cache      = Logger(subsystem: "app.cassette.cache",      category: "CacheService")
    nonisolated static let download   = Logger(subsystem: "app.cassette.download",   category: "DownloadService")
    nonisolated static let resolver   = Logger(subsystem: "app.cassette.resolver",   category: "MediaResolver")
    nonisolated static let nowPlaying = Logger(subsystem: "app.cassette.nowplaying", category: "NowPlayingService")
    nonisolated static let keychain   = Logger(subsystem: "app.cassette.keychain",   category: "KeychainService")
    nonisolated static let network     = Logger(subsystem: "app.cassette.network",    category: "NetworkMonitor")
    nonisolated static let ui         = Logger(subsystem: "app.cassette.ui",         category: "UI")
    nonisolated static let favorites   = Logger(subsystem: "app.cassette.favorites",  category: "FavoritesService")
    nonisolated static let pin         = Logger(subsystem: "app.cassette.pin",        category: "PinService")
    nonisolated static let session     = Logger(subsystem: "app.cassette.session",    category: "PlaybackSessionService")
}
