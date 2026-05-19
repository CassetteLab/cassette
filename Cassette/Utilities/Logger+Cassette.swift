// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    nonisolated static let playlist    = Logger(subsystem: "app.cassette.playlist",   category: "PlaylistService")
    nonisolated static let radio       = Logger(subsystem: "app.cassette.radio",      category: "RadioService")
    nonisolated static let discover      = Logger(subsystem: "app.cassette.discover",      category: "DiscoverViewModel")
    nonisolated static let dominantColor = Logger(subsystem: "app.cassette.dominantColor", category: "DominantColorExtractor")
    nonisolated static let stats         = Logger(subsystem: "app.cassette.stats",         category: "StatsService")
    nonisolated static let wrapped       = Logger(subsystem: "app.cassette.wrapped",       category: "WrappedPlaylistService")
    nonisolated static let wrappedStory  = Logger(subsystem: "app.cassette.wrappedstory",  category: "WrappedStoryPlayer")
    nonisolated static let lyrics        = Logger(subsystem: "app.cassette.lyrics",        category: "LyricsService")
    nonisolated static let widget           = Logger(subsystem: "app.cassette.widget",           category: "WidgetSyncService")
    nonisolated static let recommendations  = Logger(subsystem: "app.cassette.recommendations",  category: "RecommendationService")
    nonisolated static let listenBrainz     = Logger(subsystem: "app.cassette.listenbrainz",     category: "ListenBrainz")
    nonisolated static let integrations       = Logger(subsystem: "app.cassette.integrations",       category: "Integrations")
    nonisolated static let externalArtwork    = Logger(subsystem: "app.cassette.externalartwork",    category: "ExternalArtworkCache")
    nonisolated static let artistArtwork      = Logger(subsystem: "app.cassette.artistartwork",      category: "ExternalArtistImageResolver")
    nonisolated static let navidromeNative    = Logger(subsystem: "app.cassette.navidrome",          category: "NavidromeNativeAPI")
    nonisolated static let httpTransport      = Logger(subsystem: "app.cassette.transport",          category: "CustomHeadersTransport")
    nonisolated static let settings           = Logger(subsystem: "app.cassette.settings",           category: "Settings")
}
