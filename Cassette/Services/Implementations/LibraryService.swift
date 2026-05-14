// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

actor LibraryService: LibraryServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer
    private var cachedClient: SwiftSonicClient?
    private var cachedServerId: UUID?
    private var artistNameIndex: [String: ArtistID3]?
    private var artistInfoCache: [String: ArtistInfo] = [:]

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer) {
        self.serverService = serverService
        self.modelContainer = modelContainer
    }

    private func client() async throws -> SwiftSonicClient {
        let activeId = await MainActor.run { serverService.state.activeServer?.id }
        if let cached = cachedClient, cachedServerId == activeId, activeId != nil {
            return cached
        }
        let fresh = try await serverService.makeSwiftSonicClient()
        cachedClient = fresh
        cachedServerId = activeId
        artistInfoCache = [:]
        artistNameIndex = nil
        return fresh
    }

    func artists() async throws -> [ArtistIndex] {
        try await client().getArtists()
    }

    func artist(id: String) async throws -> ArtistID3 {
        try await client().getArtist(id: id)
    }

    func album(id: String) async throws -> AlbumID3 {
        try await client().getAlbum(id: id)
    }

    func playlists() async throws -> [Playlist] {
        try await client().getPlaylists()
    }

    func playlist(id: String) async throws -> PlaylistWithSongs {
        try await client().getPlaylist(id: id)
    }

    func search(_ query: String) async throws -> SearchResult3 {
        try await client().search3(query)
    }

    func coverArtURL(id: String, size: Int?) async -> URL? {
        guard let c = try? await client() else { return nil }
        return c.coverArtURL(id: id, size: size)
    }

    func streamURL(songId: String) async -> URL? {
        guard let c = try? await client() else { return nil }
        return c.streamURL(id: songId)
    }

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        try await client().star(songIds: songIds, albumIds: albumIds, artistIds: artistIds)
    }

    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        try await client().unstar(songIds: songIds, albumIds: albumIds, artistIds: artistIds)
    }

    func getStarred2() async throws -> Starred2 {
        try await client().getStarred2()
    }

    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] {
        try await client().getAlbumList2(type: .newest, size: size)
    }

    func allAlbums() async throws -> [AlbumID3] {
        try await client().getAlbumList2(type: .alphabeticalByName, size: 500)
    }

    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {
        // TODO(v1.x): verify Navidrome savePlayQueue support; implement best-effort sync
    }

    func getPlayQueue() async throws -> SavedPlayQueue? {
        // TODO(v1.x): implement best-effort queue restore from server
        return nil
    }

    // MARK: - Artist tracks

    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] {
        let artistDetail = try await artist(id: artistID)
        let albums = (artistDetail.album ?? []).sorted { lhs, rhs in
            switch (lhs.year, rhs.year) {
            case let (y1?, y2?): return y1 > y2
            case (_?, nil):      return true
            case (nil, _?):      return false
            case (nil, nil):     return lhs.name < rhs.name
            }
        }
        guard !albums.isEmpty else { return [] }

        var collected: [(index: Int, songs: [DisplayableSong])] = []

        await withTaskGroup(of: (Int, [DisplayableSong]?).self) { group in
            var submitted = 0

            while submitted < min(5, albums.count) {
                let i = submitted
                let albumId = albums[i].id
                group.addTask { await self.fetchAlbumTracks(albumId: albumId, index: i) }
                submitted += 1
            }

            while let (index, songs) = await group.next() {
                if let songs { collected.append((index, songs)) }
                if submitted < albums.count {
                    let i = submitted
                    let albumId = albums[i].id
                    group.addTask { await self.fetchAlbumTracks(albumId: albumId, index: i) }
                    submitted += 1
                }
            }
        }

        guard !collected.isEmpty else {
            Logger.library.error("[ARTIST-TRACKS] all fetches failed artistId=\(artistID, privacy: .public)")
            throw CassetteError.artistTracksUnavailable
        }

        Logger.library.debug("[ARTIST-TRACKS] fetched \(collected.count)/\(albums.count) albums artistId=\(artistID, privacy: .public)")
        return collected.sorted { $0.index < $1.index }.flatMap { $0.songs }
    }

    private func fetchAlbumTracks(albumId: String, index: Int) async -> (Int, [DisplayableSong]?) {
        do {
            let detail = try await album(id: albumId)
            let songs = (detail.song ?? []).map {
                // TODO(v1.x): resolve isDownloaded via DownloadService before queueing
                DisplayableSong(from: $0, isDownloaded: false)
            }
            return (index, songs)
        } catch {
            Logger.library.error("[ARTIST-TRACKS] album \(albumId) fetch failed: \(error, privacy: .public)")
            return (index, nil)
        }
    }

    // MARK: - Discover

    func scrobble(songId: String, submission: Bool) async {
        do {
            try await client().scrobble(id: songId, submission: submission)
            Logger.library.debug("Scrobbled '\(songId, privacy: .public)' submission=\(submission)")
        } catch {
            // Silent failure per Subsonic convention. Log at debug level only — scrobble errors
            // are common (network blips, auth races) and should never surface to the user.
            Logger.library.debug("Scrobble failed for '\(songId, privacy: .public)' submission=\(submission): \(error, privacy: .public)")
        }
    }

    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] {
        try await client().getAlbumList2(type: .recent, size: size)
    }

    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] {
        try await client().getAlbumList2(type: .frequent, size: size)
    }

    func randomSongs(size: Int) async throws -> [Song] {
        try await client().getRandomSongs(size: size)
    }

    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] {
        let isOnline = await MainActor.run { serverService.state.isOnline }
        if isOnline {
            return try await onlineSmartShuffle(targetSize: targetSize)
        } else {
            return await offlineSmartShuffle(targetSize: targetSize)
        }
    }

    private func onlineSmartShuffle(targetSize: Int) async throws -> [DisplayableSong] {
        let pool = try await client().getRandomSongs(size: 200)
        guard !pool.isEmpty else { return [] }

        let now = Date()
        let windows: [TimeInterval] = [30 * 86_400, 60 * 86_400, 90 * 86_400]

        for window in windows {
            let cutoff = now.addingTimeInterval(-window)
            let filtered = pool.filter { song in
                guard let played = song.played else { return true }
                return played < cutoff
            }
            if filtered.count >= 10 {
                Logger.library.debug("Smart shuffle online: \(filtered.count) tracks after filter (window: \(Int(window / 86_400))d)")
                return Array(filtered.shuffled().prefix(targetSize)).map { DisplayableSong(from: $0) }
            }
        }

        // Last resort: sort by played asc (nil first = never played), take target.
        let sorted = pool.sorted { lhs, rhs in
            switch (lhs.played, rhs.played) {
            case (nil, nil): return false
            case (nil, _):   return true
            case (_, nil):   return false
            case (let l?, let r?): return l < r
            }
        }
        Logger.library.debug("Smart shuffle online: pool fully recent, falling back to oldest-played first (\(sorted.count) tracks)")
        return Array(sorted.prefix(targetSize)).map { DisplayableSong(from: $0) }
    }

    // MARK: - Similar artists support

    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo {
        if let cached = artistInfoCache[artistID] {
            Logger.library.notice("[ARTIST-INFO] cache hit artistId=\(artistID, privacy: .public) similarCount=\(cached.similarArtist?.count ?? 0, privacy: .public)")
            return cached
        }
        Logger.library.notice("[ARTIST-INFO] cache miss — network call artistId=\(artistID, privacy: .public) count=\(count, privacy: .public)")
        let started = Date()
        do {
            let info = try await withThrowingTaskGroup(of: ArtistInfo.self) { group in
                group.addTask { try await self.client().getArtistInfo2(id: artistID, count: count) }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw CassetteError.timeout
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let elapsed = Date().timeIntervalSince(started)
            Logger.library.notice("[ARTIST-INFO] success artistId=\(artistID, privacy: .public) \(String(format: "%.2f", elapsed), privacy: .public)s similarCount=\(info.similarArtist?.count ?? 0, privacy: .public)")
            artistInfoCache[artistID] = info
            return info
        } catch CassetteError.timeout {
            let elapsed = Date().timeIntervalSince(started)
            Logger.library.notice("[ARTIST-INFO] TIMEOUT after \(String(format: "%.2f", elapsed), privacy: .public)s artistId=\(artistID, privacy: .public)")
            throw CassetteError.timeout
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            Logger.library.notice("[ARTIST-INFO] FAILED after \(String(format: "%.2f", elapsed), privacy: .public)s artistId=\(artistID, privacy: .public): \(error, privacy: .public)")
            throw error
        }
    }

    func getArtistMBID(forArtistID artistID: String) async throws -> String? {
        try await getArtistInfo(forArtistID: artistID, count: 20).musicBrainzId
    }

    func findArtist(byName name: String) async -> ArtistID3? {
        if artistNameIndex == nil {
            Logger.library.notice("[FIND-ARTIST] index not built — triggering build name=\(name, privacy: .public)")
            let t0 = Date()
            await buildArtistNameIndex()
            Logger.library.notice("[FIND-ARTIST] index built in \(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)s entries=\(self.artistNameIndex?.count ?? 0, privacy: .public)")
        } else {
            Logger.library.notice("[FIND-ARTIST] index ready entries=\(self.artistNameIndex?.count ?? 0, privacy: .public) name=\(name, privacy: .public)")
        }
        let normalized = Self.normalizeArtistName(name)
        if let found = artistNameIndex?[normalized] {
            Logger.library.notice("[FIND-ARTIST] FOUND '\(name, privacy: .public)' → id=\(found.id, privacy: .public)")
            return found
        }
        Logger.library.notice("[FIND-ARTIST] NOT FOUND '\(name, privacy: .public)'")
        return nil
    }

    private func buildArtistNameIndex() async {
        guard let indices = try? await artists() else { return }
        let all = indices.flatMap { $0.artist }
        artistNameIndex = Dictionary(
            all.map { (Self.normalizeArtistName($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        Logger.library.notice("[FIND-ARTIST] index built: \(all.count, privacy: .public) entries")
    }

    /// Applies diacritics-insensitive folding, lowercasing, and whitespace trimming.
    /// `internal` so it is accessible from the test target via `@testable import`.
    nonisolated static func normalizeArtistName(_ name: String) -> String {
        name
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func offlineSmartShuffle(targetSize: Int) async -> [DisplayableSong] {
        guard let activeServerId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            Logger.library.debug("Smart shuffle offline: no active server, returning empty")
            return []
        }

        let songs: [DisplayableSong] = await MainActor.run {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<DownloadedTrack>(
                predicate: #Predicate<DownloadedTrack> { $0.serverId == activeServerId }
            )
            let downloads = (try? context.fetch(descriptor)) ?? []
            guard !downloads.isEmpty else {
                Logger.library.debug("Smart shuffle offline: no downloads available")
                return []
            }
            let selected = Array(downloads.shuffled().prefix(targetSize))
            Logger.library.debug("Smart shuffle offline: \(selected.count) tracks from \(downloads.count) downloads")
            return selected.map { DisplayableSong(from: $0) }
        }

        return songs
    }
}
