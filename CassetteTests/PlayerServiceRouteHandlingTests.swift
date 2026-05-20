// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import Testing
import Foundation
import SwiftData
import AVFoundation
import SwiftSonic
@testable import Cassette

// MARK: - Minimal stubs

private final actor StubMediaResolver: MediaResolverProtocol {
    func resolve(songId: String, serverId: UUID) async throws -> MediaSource {
        throw CassetteError.serverNotConfigured
    }
    func resolveRadio(_ station: InternetRadioStation) async throws -> MediaSource {
        throw CassetteError.serverNotConfigured
    }
}

private final actor StubServerService: ServerServiceProtocol {
    nonisolated let state: ServerState
    init(state: ServerState) { self.state = state }
    func addServer(displayName: String, baseURL: String, username: String,
                   password: String, customHeaders: [String: String]) async throws {}
    func removeServer(id: UUID) async throws {}
    func setActiveServer(id: UUID) async throws {}
    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {}
    func updateServer(id: UUID, displayName: String, baseURL: String, username: String,
                      password: String, customHeaders: [String: String]) async throws {}
    func testConnection() async throws {}
    func testConnection(url: String, username: String, password: String,
                        customHeaders: [String: String]) async throws {}
    func makeSwiftSonicClient() async throws -> SwiftSonicClient {
        throw CassetteError.serverNotConfigured
    }
    func activeCredentials() async throws -> ServerCredentials {
        throw CassetteError.serverNotConfigured
    }
    func loadPersistedState() async {}
}

private final actor StubLibraryService: LibraryServiceProtocol {
    func artists() async throws -> [ArtistIndex] { [] }
    func artist(id: String) async throws -> ArtistID3 { throw CassetteError.serverNotConfigured }
    func album(id: String) async throws -> AlbumID3 { throw CassetteError.serverNotConfigured }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { [] }
    func playlists() async throws -> [Playlist] { [] }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw CassetteError.serverNotConfigured }
    func search(_ query: String) async throws -> SearchResult3 { throw CassetteError.serverNotConfigured }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func getStarred2() async throws -> Starred2 { throw CassetteError.serverNotConfigured }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func allAlbums() async throws -> [AlbumID3] { [] }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func randomSongs(size: Int) async throws -> [Song] { [] }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { [] }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo {
        throw CassetteError.serverNotConfigured
    }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
}

private final actor StubCacheService: CacheServiceProtocol {
    var usedBytes: Int64 = 0
    var trackCount: Int = 0
    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func touch(songId: String, serverId: UUID) async {}
    func store(data: Data, forSongId songId: String, serverId: UUID, mimeType: String) async throws -> URL {
        throw CassetteError.serverNotConfigured
    }
    func setMaxTracks(_ value: Int) async {}
    func invalidate(songId: String, serverId: UUID) async {}
    func clearAll() async {}
    func clearAllForServer(_ serverId: UUID) async {}
}

private final actor StubDownloadService: DownloadServiceProtocol {
    nonisolated let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { _ in }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { false }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { nil }
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { nil }
    func download(song: Song, serverId: UUID) async throws {}
    func download(album: AlbumID3, serverId: UUID) async throws {}
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws {}
    func isDownloading(songId: String, serverId: UUID) async -> Bool { false }
    func isDownloadingAlbum(_ albumId: String) async -> Bool { false }
    func isDownloadingPlaylist(_ playlistId: String) async -> Bool { false }
    func cancelDownload(songId: String, serverId: UUID) async {}
    func remove(songId: String, serverId: UUID) async throws {}
    func remove(albumId: String, serverId: UUID) async throws {}
    func remove(playlistId: String, serverId: UUID) async throws {}
}

// MARK: - Suite

@Suite("PlayerService — AirPlay route handling (H1 / H2 / H3)")
@MainActor
struct PlayerServiceRouteHandlingTests {

    private func makeService() throws -> PlayerService {
        let container = try ModelContainer.cassette(inMemory: true)
        let download = StubDownloadService()
        let library = StubLibraryService()
        return PlayerService(
            state: PlayerState(),
            mediaResolver: StubMediaResolver(),
            serverService: StubServerService(state: ServerState()),
            sessionService: PlaybackSessionService(modelContainer: container),
            artworkImageCache: ArtworkImageCache(downloadService: download, libraryService: library),
            libraryService: library,
            cacheService: StubCacheService(),
            downloadService: download,
            cacheSettings: CacheSettings(),
            toastService: ToastService(),
            statsService: StatsService(modelContainer: container)
        )
    }

    // MARK: H1 — oldDeviceUnavailable suppression

    @Test("H1: .oldDeviceUnavailable during transition is suppressed — player is not paused")
    func oldDeviceUnavailable_duringTransition_doesNotPause() async throws {
        let svc = try makeService()
        // Simulate: transition is in progress (new player just started, AirPlay stream resetting)
        await svc.setTestTransitioningTrack(true)
        await svc.setTestPlayingIntent(true)

        await svc.handleRouteChange(.oldDeviceUnavailable)

        // State must NOT be paused — the notification was a teardown artefact, not a real disconnect
        let playbackState = await MainActor.run { svc.state.playbackState }
        #expect(playbackState != .paused)
    }

    @Test("H1: .oldDeviceUnavailable outside transition pauses playback")
    func oldDeviceUnavailable_outsideTransition_pauses() async throws {
        let svc = try makeService()
        await svc.setTestTransitioningTrack(false)
        await svc.setTestPlayingIntent(true)
        // Seed a non-idle state so the pause() call has something meaningful to set
        await MainActor.run { svc.state.playbackState = .playing }

        await svc.handleRouteChange(.oldDeviceUnavailable)

        let playbackState = await MainActor.run { svc.state.playbackState }
        #expect(playbackState == .paused)
    }

    @Test("H1: isTransitioningTrack is cleared when timeControlStatus reaches .playing")
    func timeControlStatus_playing_clearsTransitioningTrack() async throws {
        let svc = try makeService()
        await svc.setTestTransitioningTrack(true)

        await svc.handleTimeControlStatus(.playing, waitingReason: nil)

        let isTransitioning = await svc.testIsTransitioningTrack
        #expect(!isTransitioning)
    }

    @Test("H1: isTransitioningTrack persists when timeControlStatus is .waitingToPlayAtSpecifiedRate")
    func timeControlStatus_waiting_doesNotClearTransitioningTrack() async throws {
        let svc = try makeService()
        await svc.setTestTransitioningTrack(true)
        // Prevent stall recovery task from being created (no intent)
        await svc.setTestPlayingIntent(false)

        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)

        let isTransitioning = await svc.testIsTransitioningTrack
        #expect(isTransitioning)
    }

    // MARK: H2 — timeControlStatus stall recovery

    @Test("H2: stall recovery task is created when player waits with playing intent")
    func waitingToPlayAtSpecifiedRate_withIntent_createsStallTask() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(true)

        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)

        let hasTask = await svc.testHasStallRecoveryTask
        #expect(hasTask)
    }

    @Test("H2: stall recovery task is NOT created when intent is paused")
    func waitingToPlayAtSpecifiedRate_withoutIntent_noStallTask() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(false)

        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)

        let hasTask = await svc.testHasStallRecoveryTask
        #expect(!hasTask)
    }

    @Test("H2: .playing cancels any active stall recovery task")
    func timeControlStatus_playing_cancelsStallTask() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(true)
        // Create a stall task first
        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)
        let hadTask = await svc.testHasStallRecoveryTask
        #expect(hadTask)

        // Confirm .playing clears it
        await svc.handleTimeControlStatus(.playing, waitingReason: nil)
        let hasTask = await svc.testHasStallRecoveryTask
        #expect(!hasTask)
    }

    @Test("H2: .paused cancels any active stall recovery task")
    func timeControlStatus_paused_cancelsStallTask() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(true)
        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)

        await svc.handleTimeControlStatus(.paused, waitingReason: nil)

        let hasTask = await svc.testHasStallRecoveryTask
        #expect(!hasTask)
    }

    @Test("H2: duplicate .waitingToPlayAtSpecifiedRate does not create a second stall task")
    func duplicateWaiting_onlyOneStallTask() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(true)

        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)
        let taskAfterFirst = await svc.testHasStallRecoveryTask
        await svc.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate, waitingReason: nil)
        let taskAfterSecond = await svc.testHasStallRecoveryTask

        // Both checks should be true — one task, not crashed/nil after duplicate
        #expect(taskAfterFirst)
        #expect(taskAfterSecond)
    }

    // MARK: H3 — route becomes available

    @Test("H3: .newDeviceAvailable with playing intent runs without error (no mock player, verifies no crash)")
    func newDeviceAvailable_withPlayingIntent_doesNotCrash() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(true)

        // No player is set up (no crash expected — player is nil, conditional is guarded)
        await svc.handleRouteChange(.newDeviceAvailable)
    }

    @Test("H3: .routeConfigurationChange with playing intent runs without error")
    func routeConfigurationChange_withPlayingIntent_doesNotCrash() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(true)

        await svc.handleRouteChange(.routeConfigurationChange)
    }

    @Test("H3: .newDeviceAvailable without playing intent does not alter playbackState")
    func newDeviceAvailable_withoutIntent_noStateChange() async throws {
        let svc = try makeService()
        await svc.setTestPlayingIntent(false)
        await MainActor.run { svc.state.playbackState = .idle }

        await svc.handleRouteChange(.newDeviceAvailable)

        let state = await MainActor.run { svc.state.playbackState }
        #expect(state == .idle)
    }

    @Test("H3: isPlayingIntent is updated by pause() and resume()")
    func intentTracksUserActions() async throws {
        let svc = try makeService()

        await svc.setTestPlayingIntent(true)
        #expect(await svc.testIsPlayingIntent)

        await svc.pause()
        #expect(!(await svc.testIsPlayingIntent))

        await svc.resume()
        #expect(await svc.testIsPlayingIntent)
    }
}
#endif
