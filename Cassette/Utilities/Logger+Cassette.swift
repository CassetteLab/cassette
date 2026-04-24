import OSLog

extension Logger {
    static let server     = Logger(subsystem: "app.cassette.server",     category: "ServerService")
    static let player     = Logger(subsystem: "app.cassette.player",     category: "PlayerService")
    static let library    = Logger(subsystem: "app.cassette.library",    category: "LibraryService")
    static let cache      = Logger(subsystem: "app.cassette.cache",      category: "CacheService")
    static let download   = Logger(subsystem: "app.cassette.download",   category: "DownloadService")
    static let resolver   = Logger(subsystem: "app.cassette.resolver",   category: "MediaResolver")
    static let nowPlaying = Logger(subsystem: "app.cassette.nowplaying", category: "NowPlayingService")
    static let keychain   = Logger(subsystem: "app.cassette.keychain",   category: "KeychainService")
    static let ui         = Logger(subsystem: "app.cassette.ui",         category: "UI")
}
