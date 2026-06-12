// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

actor LibraryService: LibraryServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer
    private let downloadService: any DownloadServiceProtocol
    private let statsService: StatsService
    private var cachedClient: SwiftSonicClient?
    private var artistNameIndex: [String: ArtistID3]?
    private var indexBuildTask: Task<Void, Never>?
    private var artistInfoCache: [String: ArtistInfo] = [:]

    init(
        serverService: any ServerServiceProtocol,
        modelContainer: ModelContainer,
        downloadService: any DownloadServiceProtocol,
        statsService: StatsService
    ) {
        self.serverService = serverService
        self.modelContainer = modelContainer
        self.downloadService = downloadService
        self.statsService = statsService
    }

    private func client() async throws -> SwiftSonicClient {
        // Fast path: cached client returned without touching the MainActor.
        // The periodic player time observer fires on the MainActor every 0.5s during playback,
        // so any await MainActor.run on the hot path causes multi-second stalls.
        if let cached = cachedClient {
            Logger.library.debug("[CLIENT] cache hit")
            return cached
        }
        Logger.library.debug("[CLIENT] cache miss → makeSwiftSonicClient")
        let fresh = try await serverService.makeSwiftSonicClient()
        Logger.library.debug("[CLIENT] ← makeSwiftSonicClient done")
        cachedClient = fresh
        artistInfoCache = [:]
        artistNameIndex = nil
        indexBuildTask = nil
        return fresh
    }

    func artists() async throws -> [ArtistIndex] {
        try await client().getArtists()
    }

    func artist(id: String) async throws -> ArtistID3 {
        Logger.library.debug("[ARTIST] artist(id:) START id=\(id, privacy: .public)")
        let c = try await client()
        Logger.library.debug("[ARTIST] → client().getArtist")
        let t0 = Date()
        let result = try await c.getArtist(id: id)
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
        Logger.library.debug("[ARTIST] ← client().getArtist done \(elapsed, privacy: .public)s")
        return result
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
        Logger.library.info("allAlbums() called")
        do {
            let result = try await client().getAlbumList2(type: .alphabeticalByName, size: 500)
            Logger.library.info("allAlbums() done — \(result.count, privacy: .public) items")
            return result
        } catch {
            Logger.library.error("allAlbums() getAlbumList2 error: \(String(describing: error), privacy: .public)")
            Logger.library.error("allAlbums() error type: \(type(of: error), privacy: .public)")
            throw error
        }
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
            let serverId = await MainActor.run { serverService.state.activeServer?.id }
            var songs: [DisplayableSong] = []
            for song in detail.song ?? [] {
                var downloaded = false
                if let serverId {
                    downloaded = await downloadService.isDownloaded(songId: song.id, serverId: serverId)
                }
                songs.append(DisplayableSong(from: song, isDownloaded: downloaded))
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
        // Product rule: rediscover is TRULY random — no recency weighting,
        // no `played` filtering. The server picks uniformly across the library.
        let songs = try await client().getRandomSongs(size: targetSize)
        Logger.library.debug("Smart shuffle online: \(songs.count) random tracks (target \(targetSize))")
        return songs.map { DisplayableSong(from: $0) }
    }

    // MARK: - Auto-extend similar backfill

    /// Most recent distinct seed values win; bounds keep the candidate fan-out cheap
    /// (each artist seed costs one discography fetch, each genre one getSongsByGenre).
    nonisolated static let backfillMaxSeedArtists = 5
    nonisolated static let backfillMaxSeedGenres = 3
    nonisolated static let backfillGenreFetchCount = 100

    /// Extracts distinct artist ids and genres from recent plays, newest first.
    nonisolated static func similaritySeeds(
        from events: [PlaybackEventDTO],
        maxArtists: Int = backfillMaxSeedArtists,
        maxGenres: Int = backfillMaxSeedGenres
    ) -> (artistIds: [String], genres: [String]) {
        var artistIds: [String] = []
        var genres: [String] = []
        for event in events {
            if let id = event.artistId, !id.isEmpty, artistIds.count < maxArtists, !artistIds.contains(id) {
                artistIds.append(id)
            }
            if let genre = event.genre, !genre.isEmpty, genres.count < maxGenres, !genres.contains(genre) {
                genres.append(genre)
            }
        }
        return (artistIds, genres)
    }

    /// Shuffles the candidate pool, drops excluded and duplicate ids, and caps at
    /// `targetSize`. Pure — the network-facing caller assembles the inputs.
    nonisolated static func assembleBackfill(
        pool: [DisplayableSong],
        excludedIds: Set<String>,
        targetSize: Int
    ) -> [DisplayableSong] {
        var seen = excludedIds
        var result: [DisplayableSong] = []
        for song in pool.shuffled() where !seen.contains(song.id) {
            seen.insert(song.id)
            result.append(song)
            if result.count == targetSize { break }
        }
        return result
    }

    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] {
        let isOnline = await MainActor.run { serverService.state.isOnline }
        guard isOnline else {
            // Offline: keep the downloads-only fallback, still honoring exclusions.
            let downloads = await offlineSmartShuffle(targetSize: targetSize + excludedIds.count)
            return Self.assembleBackfill(pool: downloads, excludedIds: excludedIds, targetSize: targetSize)
        }
        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            return []
        }

        let recent = await statsService.recentEvents(limit: 20, serverId: serverId.uuidString)
        // Never re-serve what the user just heard.
        var excluded = excludedIds
        for event in recent { excluded.insert(event.trackId) }

        // No ≥30s listening history yet → degrade to pure random.
        let seeds = Self.similaritySeeds(from: recent)
        var pool: [DisplayableSong] = []
        if !recent.isEmpty {
            // Artist candidates: full discographies via the existing bounded fetcher.
            // Deliberately NOT getTopSongs — popularity-backed per spec, empty on bare
            // self-hosted servers; kept out so the heuristic works everywhere.
            for artistId in seeds.artistIds {
                if let tracks = try? await fetchAllTracks(forArtistID: artistId) {
                    pool.append(contentsOf: tracks)
                }
            }
            // Genre candidates from local tags.
            for genre in seeds.genres {
                if let songs = try? await client().getSongsByGenre(genre, count: Self.backfillGenreFetchCount) {
                    pool.append(contentsOf: songs.map { DisplayableSong(from: $0) })
                }
            }
        }

        var result = Self.assembleBackfill(pool: pool, excludedIds: excluded, targetSize: targetSize)

        // Thin pool (small library, empty genres) or no history: top up with random.
        if result.count < targetSize {
            let randomSongs = (try? await client().getRandomSongs(size: targetSize + excluded.count)) ?? []
            excluded.formUnion(result.map(\.id))
            let topUp = Self.assembleBackfill(
                pool: randomSongs.map { DisplayableSong(from: $0) },
                excludedIds: excluded,
                targetSize: targetSize - result.count
            )
            result.append(contentsOf: topUp)
        }

        Logger.library.debug("Similar backfill: \(result.count)/\(targetSize) tracks (seeds: \(seeds.artistIds.count) artists, \(seeds.genres.count) genres, recent: \(recent.count))")
        return result
    }

    // MARK: - Similar artists support

    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo {
        if let cached = artistInfoCache[artistID] {
            Logger.library.debug("[ARTIST-INFO] cache hit artistId=\(artistID, privacy: .public) similarCount=\(cached.similarArtist?.count ?? 0, privacy: .public)")
            return cached
        }
        Logger.library.debug("[ARTIST-INFO] cache miss — network call artistId=\(artistID, privacy: .public) count=\(count, privacy: .public)")
        let started = Date()
        do {
            let info = try await client().getArtistInfo2(id: artistID, count: count)
            let elapsed = Date().timeIntervalSince(started)
            Logger.library.debug("[ARTIST-INFO] success artistId=\(artistID, privacy: .public) \(String(format: "%.2f", elapsed), privacy: .public)s similarCount=\(info.similarArtist?.count ?? 0, privacy: .public)")
            artistInfoCache[artistID] = info
            return info
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            Logger.library.warning("[ARTIST-INFO] FAILED after \(String(format: "%.2f", elapsed), privacy: .public)s artistId=\(artistID, privacy: .public): \(error, privacy: .public)")
            throw error
        }
    }

    func getArtistMBID(forArtistID artistID: String) async throws -> String? {
        try await getArtistInfo(forArtistID: artistID, count: 20).musicBrainzId
    }

    func findArtist(byName name: String) async -> ArtistID3? {
        if artistNameIndex == nil {
            if indexBuildTask == nil {
                Logger.library.debug("[FIND-ARTIST] index not built — starting build name=\(name, privacy: .public)")
                indexBuildTask = Task { await self.buildArtistNameIndex() }
            } else {
                Logger.library.debug("[FIND-ARTIST] awaiting in-progress build name=\(name, privacy: .public)")
            }
            _ = await indexBuildTask?.value
            indexBuildTask = nil
        } else {
            Logger.library.debug("[FIND-ARTIST] index ready entries=\(self.artistNameIndex?.count ?? 0, privacy: .public) name=\(name, privacy: .public)")
        }
        let normalized = Self.normalizeArtistName(name)
        if let found = artistNameIndex?[normalized] {
            Logger.library.debug("[FIND-ARTIST] FOUND '\(name, privacy: .public)' → id=\(found.id, privacy: .public)")
            return found
        }
        Logger.library.debug("[FIND-ARTIST] NOT FOUND '\(name, privacy: .public)'")
        return nil
    }

    private func buildArtistNameIndex() async {
        guard let indices = try? await artists() else { return }
        let all = indices.flatMap { $0.artist }
        var index: [String: ArtistID3] = [:]
        index.reserveCapacity(all.count)
        for (i, a) in all.enumerated() {
            let key = Self.normalizeArtistName(a.name)
            if index[key] == nil { index[key] = a }
            if i % 200 == 0 && i > 0 { await Task.yield() }
        }
        artistNameIndex = index
        Logger.library.info("[FIND-ARTIST] index built: \(all.count, privacy: .public) entries")
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
