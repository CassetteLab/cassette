// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

// TODO(v1.x): switch to background URLSession with resume-after-kill support.
// v1 uses foreground URLSession — the user must keep the app open during download.
actor DownloadService: DownloadServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer
    private let downloadsDirectory: URL
    private let coverArtsDirectory: URL
    private var progressContinuation: AsyncStream<[DownloadProgress]>.Continuation?
    /// Keyed by "songId::serverId" to allow per-track cancellation.
    private var inFlightTasks: [String: Task<Void, Error>] = [:]
    private var activeAlbumDownloads: Set<String> = []
    private var activePlaylistDownloads: Set<String> = []
    private let toastService: ToastService
    private let downloadSession: URLSession

    nonisolated let progressStream: AsyncStream<[DownloadProgress]>

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer, toastService: ToastService) {
        self.serverService = serverService
        self.modelContainer = modelContainer
        self.toastService = toastService

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 30
        self.downloadSession = URLSession(configuration: sessionConfig)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = docs.appendingPathComponent("app.cassette", isDirectory: true)
        self.downloadsDirectory = base.appendingPathComponent("downloads", isDirectory: true)
        self.coverArtsDirectory = base.appendingPathComponent("coverarts", isDirectory: true)

        // AsyncStream.init closure is called synchronously — cont is guaranteed set before init returns.
        var cont: AsyncStream<[DownloadProgress]>.Continuation!
        progressStream = AsyncStream<[DownloadProgress]> { cont = $0 }
        progressContinuation = cont
    }

    // MARK: - Lookup

    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? {
        let entry: (filePath: String, fileSize: Int64)? = await MainActor.run {
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<DownloadedTrack> { $0.songId == songId }
            let tracks = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
            return tracks.first(where: { $0.serverId == serverId }).map { ($0.filePath, $0.fileSize) }
        }
        guard let entry else { return nil }
        let url = downloadsDirectory.appendingPathComponent(entry.filePath)
        // A missing, empty, or size-mismatched file must fall through to cache/stream —
        // never hand a broken local file to the player. The file is NOT deleted here
        // (permanent downloads are user data); the record's size 0 means a legacy entry
        // whose size read failed at write time, where only non-emptiness can be checked.
        let diskSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard diskSize > 0, entry.fileSize == 0 || diskSize == entry.fileSize else {
            Logger.download.warning("Downloaded track record exists but file missing or invalid (disk \(diskSize) bytes, record \(entry.fileSize)): \(entry.filePath, privacy: .public)")
            return nil
        }
        return url
    }

    func isDownloaded(songId: String, serverId: UUID) async -> Bool {
        await downloadedURL(forSongId: songId, serverId: serverId) != nil
    }

    func downloadedSongIds(serverId: UUID) async -> Set<String> {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let all = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
            return Set(all.filter { $0.serverId == serverId }.map(\.songId))
        }
    }

    func localCoverArtURL(forId coverArtId: String) async -> URL? {
        let url = coverArtsDirectory.appendingPathComponent(coverArtId)
        let exists = FileManager.default.fileExists(atPath: url.path)
        Logger.download.debug("localCoverArtURL id='\(coverArtId, privacy: .public)' path='\(url.path, privacy: .public)' exists=\(exists)")
        return exists ? url : nil
    }

    func persistCover(_ data: Data, forId coverArtId: String) async {
        let url = coverArtsDirectory.appendingPathComponent(coverArtId)
        Logger.download.debug("persistCover id='\(coverArtId, privacy: .public)' path='\(url.path, privacy: .public)' bytes=\(data.count, privacy: .public)")
        do {
            try FileManager.default.createDirectory(at: coverArtsDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.download.debug("Failed to persist cover '\(coverArtId, privacy: .public)': \(error, privacy: .public)")
        }
    }

    func removeCover(forId coverArtId: String) async {
        let url = coverArtsDirectory.appendingPathComponent(coverArtId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.download.debug("Failed to remove cover '\(coverArtId, privacy: .public)': \(error, privacy: .public)")
        }
    }

    @discardableResult
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: coverArtsDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var deletedCount = 0
        for fileURL in entries {
            let filename = fileURL.lastPathComponent
            // Skip tier-suffixed files (id@thumb, id@hero) — those are streaming cache
            // managed by ArtworkImageCache's own eviction, not offline-download GC.
            guard !filename.contains("@") else { continue }
            let coverArtId = filename
            if !referencedIds.contains(coverArtId) {
                do {
                    try fm.removeItem(at: fileURL)
                } catch {
                    Logger.download.debug("DownloadService: garbageCollect removeItem failed — \(error)")
                }
                deletedCount += 1
            }
        }
        if deletedCount > 0 {
            Logger.download.info("Garbage collected \(deletedCount) orphaned cover(s).")
        }
        return deletedCount
    }

    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            // Tracks are the primary source — present whether the album was downloaded
            // directly or via a playlist download that never created a DownloadedAlbum record.
            let allTracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
            let albumTracks = allTracks
                .filter { $0.albumId == albumId && $0.serverId == serverId }
                .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
            guard !albumTracks.isEmpty else { return nil }
            let first = albumTracks[0]
            // DownloadedAlbum record may exist for richer metadata (direct album downloads).
            let allAlbums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
            let albumRecord = allAlbums.first(where: { $0.albumId == albumId && $0.serverId == serverId })
            let songs = albumTracks.map { DisplayableSong(from: $0) }
            return LocalAlbumData(
                albumId: albumId,
                albumName: albumRecord?.name ?? first.album ?? albumId,
                artistName: albumRecord?.artist ?? first.artist,
                coverArtId: albumRecord?.coverArtId ?? first.coverArtId,
                songs: songs
            )
        }
    }

    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let allTracks = ((try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? [])
                .filter { $0.serverId == serverId }
            // Match on artistId first; fall back to the name only for tracks whose server omitted the id,
            // so a correctly-tagged track is never pulled in by a namesake.
            let artistTracks = allTracks.filter { track in
                if let id = track.artistId { return id == artistId }
                guard let artistName, let trackArtist = track.artist else { return false }
                return trackArtist.localizedCaseInsensitiveCompare(artistName) == .orderedSame
            }
            guard !artistTracks.isEmpty else { return nil }

            let allAlbums = ((try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? [])
                .filter { $0.serverId == serverId }
            // Tracks with no albumId can't be grouped — they still play from `tracks` below.
            let byAlbum = Dictionary(grouping: artistTracks.filter { $0.albumId != nil }) { $0.albumId! }
            let albums = byAlbum
                .map { albumId, tracks -> LocalAlbumData in
                    let ordered = tracks.sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                    let first = ordered[0]
                    let record = allAlbums.first { $0.albumId == albumId }
                    return LocalAlbumData(
                        albumId: albumId,
                        albumName: record?.name ?? first.album ?? albumId,
                        artistName: record?.artist ?? first.artist,
                        coverArtId: record?.coverArtId ?? first.coverArtId,
                        songs: ordered.map { DisplayableSong(from: $0) }
                    )
                }
                .sorted { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }

            return LocalArtistData(
                artistId: artistId,
                artistName: artistName ?? artistTracks[0].artist ?? artistId,
                coverArtId: albums.first?.coverArtId ?? artistTracks[0].coverArtId,
                albums: albums,
                tracks: albums.flatMap(\.songs)
            )
        }
    }

    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let allPlaylists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
            guard let playlist = allPlaylists.first(where: { $0.playlistId == playlistId && $0.serverId == serverId }) else { return nil }
            // serverId-scoped lookup table — O(1) per id and avoids matching a track that was
            // re-downloaded under a different server with a colliding songId.
            let tracksBySongId = Dictionary(
                (((try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? [])
                    .filter { $0.serverId == serverId })
                    .map { ($0.songId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let songs = playlist.songIds.compactMap { tracksBySongId[$0] }.map { DisplayableSong(from: $0) }
            return LocalPlaylistData(playlistId: playlist.playlistId, name: playlist.name, coverArtId: playlist.coverArtId, songs: songs)
        }
    }

    func backfillPlaylistSongIds(playlistId: String, serverId: UUID, orderedSongIds: [String]) async {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
            // Only repair records that are actually missing their order. DownloadedTrack carries
            // no playlist link, so membership cannot be recovered from disk alone — the order must
            // come from the authoritative API list, intersected with what is actually downloaded.
            guard let record = playlists.first(where: { $0.playlistId == playlistId && $0.serverId == serverId }),
                  record.songIds.isEmpty else { return }
            let downloaded = Set(
                (((try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? [])
                    .filter { $0.serverId == serverId })
                    .map(\.songId)
            )
            let repaired = orderedSongIds.filter { downloaded.contains($0) }
            guard !repaired.isEmpty else { return }
            record.songIds = repaired
            do {
                try context.save()
                Logger.download.info("Back-filled \(repaired.count, privacy: .public) songId(s) for playlist '\(playlistId, privacy: .public)'")
            } catch {
                Logger.download.debug("DownloadService: songIds back-fill save failed — \(error)")
            }
        }
    }

    // MARK: - Single track download

    func download(song: Song, serverId: UUID) async throws {
        guard await !isDownloaded(songId: song.id, serverId: serverId) else {
            Logger.download.debug("Song '\(song.id, privacy: .public)' already downloaded — skipping.")
            return
        }

        let key = taskKey(songId: song.id, serverId: serverId)
        // If already in-flight, do nothing — caller can observe progressStream.
        guard inFlightTasks[key] == nil else { return }

        let task = Task<Void, Error> {
            try await self._downloadSong(song, serverId: serverId, key: key)
        }
        inFlightTasks[key] = task
        try await task.value
    }

    private func _downloadSong(_ song: Song, serverId: UUID, key: String) async throws {
        defer { inFlightTasks.removeValue(forKey: key) }

        let creds = try await serverService.activeCredentials()
        let client = try await serverService.makeSwiftSonicClient()
        guard let streamURL = client.streamURL(id: song.id) else {
            throw CassetteError.mediaNotFound(songId: song.id)
        }

        var request = URLRequest(url: streamURL)
        for (k, v) in creds.customHeaders { request.setValue(v, forHTTPHeaderField: k) }

        emit(progress: DownloadProgress(songId: song.id, serverId: serverId, progress: 0, totalBytes: nil, receivedBytes: 0))

        let (tempURL, response) = try await downloadSession.download(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            struct HTTPError: Error & Sendable { let statusCode: Int }
            throw CassetteError.downloadFailed(songId: song.id, underlying: HTTPError(statusCode: code))
        }

        // Never save a poisoned payload as a permanent download (Subsonic error-as-200
        // envelope, empty or truncated body) — unlike the cache it is never evicted,
        // so a broken file would play as silence forever.
        do {
            try AudioResponseValidator.validate(fileAt: tempURL, response: response, songId: song.id, logger: Logger.download)
        } catch {
            throw CassetteError.downloadFailed(songId: song.id, underlying: error)
        }

        let mimeType = response.mimeType ?? "audio/mpeg"
        // Prefer the server-declared suffix (e.g. "mp3", "flac") over the MIME subtype.
        // audio/mpeg → "mpeg" which AVPlayer maps to a video UTI, not public.mp3.
        let ext = song.suffix ?? mimeType.split(separator: "/").last.map(String.init) ?? "bin"
        let relativePath = "\(serverId.uuidString)/\(song.id).\(ext)"
        let fileURL = downloadsDirectory.appendingPathComponent(relativePath)

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)

        // Faststart-remux non-faststart m4a in place so AudioStreaming can play it offline
        // (lossless passthrough; no-op for every other format). MUST run before the fileSize
        // read below so DownloadedTrack.fileSize matches the on-disk (remuxed) file — otherwise
        // downloadedURL's size-validity guard would reject the remuxed file as a mismatch.
        // Logged for every outcome, not just .remuxed: knowing the remuxer ran and decided to do
        // nothing is what distinguishes "the file was already fine" from "the remuxer never fired".
        let remuxOutcome = await AudioFaststartRemuxer().remuxToFaststartIfNeeded(at: fileURL)
        Logger.download.info("Remux outcome v\(AudioFaststartRemuxer.diagnosticsVersion) for '\(song.id, privacy: .public)' (suffix: \(song.suffix ?? "nil", privacy: .public)): \(String(describing: remuxOutcome), privacy: .public)")

        // Capture only Sendable values for the MainActor closure.
        let songId = song.id
        let albumId = song.albumId
        let artistId = song.artistId
        let title = song.title
        let artist = song.artist
        let album = song.album
        let genre = song.genres?.first?.name ?? song.genre
        let track = song.track
        let duration = song.duration
        let coverArtId = song.coverArt
        let suffix = song.suffix
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let rgTrackGain    = song.replayGain?.trackGain
        let rgTrackPeak    = song.replayGain?.trackPeak
        let rgAlbumGain    = song.replayGain?.albumGain
        let rgAlbumPeak    = song.replayGain?.albumPeak
        let rgBaseGain     = song.replayGain?.baseGain
        let rgFallbackGain = song.replayGain?.fallbackGain

        // Best-effort: persist cover art so it's available offline (compilations, playlist tracks).
        // song.coverArt may differ from album.coverArt on some servers — download it per track.
        // _downloadCoverArt is idempotent (physical file check), so no redundant network hit
        // when all tracks in a standard album share the same coverArtId.
        if let cid = coverArtId {
            do {
                try await _downloadCoverArt(id: cid)
            } catch {
                Logger.download.error("Cover art download failed for song '\(songId, privacy: .public)' (coverArtId: \(cid, privacy: .public)): \(error, privacy: .public)")
            }
        }

        await MainActor.run {
            let record = DownloadedTrack(
                songId: songId,
                serverId: serverId,
                albumId: albumId,
                filePath: relativePath,
                fileSize: fileSize,
                mimeType: mimeType,
                title: title,
                artist: artist,
                artistId: artistId,
                album: album,
                trackNumber: track,
                durationSeconds: duration,
                coverArtId: coverArtId,
                suffix: suffix,
                genre: genre,
                replayGainTrackGain: rgTrackGain,
                replayGainTrackPeak: rgTrackPeak,
                replayGainAlbumGain: rgAlbumGain,
                replayGainAlbumPeak: rgAlbumPeak,
                replayGainBaseGain: rgBaseGain,
                replayGainFallbackGain: rgFallbackGain
            )
            modelContainer.mainContext.insert(record)
            do {
                try modelContainer.mainContext.save()
            } catch {
                Logger.download.error("DownloadService: track record save failed for '\(songId, privacy: .public)' — \(error)")
            }
        }

        emit(progress: DownloadProgress(songId: song.id, serverId: serverId, progress: 1.0, totalBytes: fileSize, receivedBytes: fileSize))
        Logger.download.info("Downloaded '\(song.id, privacy: .public)' (\(fileSize) bytes)")
    }

    // MARK: - Album download

    func download(album: AlbumID3, serverId: UUID) async throws {
        guard let songs = album.song else { return }
        activeAlbumDownloads.insert(album.id)
        defer { activeAlbumDownloads.remove(album.id) }
        let total = songs.count
        var succeeded = 0
        let aid = album.id

        let maxConcurrent = 3
        await withTaskGroup(of: Bool.self) { group in
            var iterator = songs.makeIterator()

            for _ in 0..<maxConcurrent {
                guard let song = iterator.next() else { break }
                group.addTask {
                    do {
                        try await self.download(song: song, serverId: serverId)
                        return true
                    } catch {
                        Logger.download.error("Failed song '\(song.id, privacy: .public)' in album '\(aid, privacy: .public)': \(error, privacy: .public)")
                        return false
                    }
                }
            }

            for await didSucceed in group {
                if didSucceed { succeeded += 1 }
                if let song = iterator.next() {
                    group.addTask {
                        do {
                            try await self.download(song: song, serverId: serverId)
                            return true
                        } catch {
                            Logger.download.error("Failed song '\(song.id, privacy: .public)' in album '\(aid, privacy: .public)': \(error, privacy: .public)")
                            return false
                        }
                    }
                }
            }
        }

        var localCoverPath: String? = nil
        if let coverArtId = album.coverArt {
            do {
                try await _downloadCoverArt(id: coverArtId)
                localCoverPath = coverArtId
            } catch {
                Logger.download.error("Cover art download failed for album '\(album.id, privacy: .public)' (coverArtId: \(coverArtId, privacy: .public)): \(error, privacy: .public)")
            }
        }

        let albumId = album.id
        let albumName = album.name
        let albumArtist = album.artist
        let coverArt = album.coverArt
        let tracksSucceeded = succeeded
        let totalTracks = total
        let coverPath = localCoverPath

        await MainActor.run {
            let context = ModelContext(modelContainer)
            let existing = (try? context.fetch(FetchDescriptor<DownloadedAlbum>()))?
                .first(where: { $0.albumId == albumId && $0.serverId == serverId })

            if let existing {
                existing.tracksCount = tracksSucceeded
                existing.totalTracksCount = totalTracks
                existing.downloadedAt = Date()
                if let coverPath { existing.localCoverArtPath = coverPath }
            } else {
                let record = DownloadedAlbum(
                    albumId: albumId,
                    serverId: serverId,
                    name: albumName,
                    artist: albumArtist,
                    tracksCount: tracksSucceeded,
                    totalTracksCount: totalTracks,
                    coverArtId: coverArt,
                    localCoverArtPath: coverPath
                )
                context.insert(record)
            }
            do {
                try context.save()
            } catch {
                Logger.download.debug("DownloadService: album record save failed — \(error)")
            }
        }
        Logger.download.info("Album '\(album.id, privacy: .public)': \(succeeded)/\(total) tracks downloaded.")
        if succeeded == total {
            await toastService.showSuccess(String(localized: "\(album.name) downloaded"))
        }
    }

    // MARK: - Playlist download

    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws {
        let songs = playlist.entry ?? []
        let total = songs.count
        let pid = playlist.id
        activePlaylistDownloads.insert(playlist.id)
        defer { activePlaylistDownloads.remove(playlist.id) }

        let maxConcurrent = 3
        await withTaskGroup(of: Void.self) { group in
            var iterator = songs.makeIterator()

            for _ in 0..<maxConcurrent {
                guard let song = iterator.next() else { break }
                group.addTask {
                    do {
                        try await self.download(song: song, serverId: serverId)
                    } catch {
                        Logger.download.error("Failed song '\(song.id, privacy: .public)' in playlist '\(pid, privacy: .public)': \(error, privacy: .public)")
                    }
                }
            }

            for await _ in group {
                if let song = iterator.next() {
                    group.addTask {
                        do {
                            try await self.download(song: song, serverId: serverId)
                        } catch {
                            Logger.download.error("Failed song '\(song.id, privacy: .public)' in playlist '\(pid, privacy: .public)': \(error, privacy: .public)")
                        }
                    }
                }
            }
        }

        let downloadedIds = await downloadedSongIds(serverId: serverId)
        let succeededIds = songs.filter { downloadedIds.contains($0.id) }.map(\.id)

        var localCoverPath: String? = nil
        if let coverArtId = playlist.coverArt {
            do {
                try await _downloadCoverArt(id: coverArtId)
                localCoverPath = coverArtId
            } catch {
                Logger.download.error("Cover art download failed for playlist '\(playlist.id, privacy: .public)' (coverArtId: \(coverArtId, privacy: .public)): \(error, privacy: .public)")
            }
        }

        let playlistId = playlist.id
        let playlistName = playlist.name
        let comment = playlist.comment
        let coverArt = playlist.coverArt
        let tracksSucceeded = succeededIds.count
        let totalTracks = total
        let ids = succeededIds
        let coverPath = localCoverPath

        await MainActor.run {
            let context = ModelContext(modelContainer)
            let existing = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>()))?
                .first(where: { $0.playlistId == playlistId && $0.serverId == serverId })

            if let existing {
                existing.tracksCount = tracksSucceeded
                existing.totalTracksCount = totalTracks
                existing.downloadedAt = Date()
                existing.songIds = ids
                if let coverPath { existing.localCoverArtPath = coverPath }
            } else {
                let record = DownloadedPlaylist(
                    playlistId: playlistId,
                    serverId: serverId,
                    name: playlistName,
                    comment: comment,
                    tracksCount: tracksSucceeded,
                    totalTracksCount: totalTracks,
                    coverArtId: coverArt,
                    localCoverArtPath: coverPath,
                    songIds: ids
                )
                context.insert(record)
            }
            do {
                try context.save()
            } catch {
                Logger.download.debug("DownloadService: playlist record save failed — \(error)")
            }
        }
        Logger.download.info("Playlist '\(playlist.id, privacy: .public)': \(tracksSucceeded)/\(total) tracks downloaded.")
        if tracksSucceeded == totalTracks {
            await toastService.showSuccess(String(localized: "\(playlist.name) downloaded"))
        }
    }

    func isDownloading(songId: String, serverId: UUID) async -> Bool {
        inFlightTasks[taskKey(songId: songId, serverId: serverId)] != nil
    }

    func isDownloadingAlbum(_ albumId: String) async -> Bool {
        activeAlbumDownloads.contains(albumId)
    }

    func isDownloadingPlaylist(_ playlistId: String) async -> Bool {
        activePlaylistDownloads.contains(playlistId)
    }

    // MARK: - Cancel

    func cancelDownload(songId: String, serverId: UUID) async {
        let key = taskKey(songId: songId, serverId: serverId)
        inFlightTasks[key]?.cancel()
        inFlightTasks.removeValue(forKey: key)
    }

    // MARK: - Remove

    func remove(songId: String, serverId: UUID) async throws {
        let filePath: String? = await MainActor.run {
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<DownloadedTrack> { $0.songId == songId }
            let tracks = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
            return tracks.first(where: { $0.serverId == serverId })?.filePath
        }
        if let filePath {
            let fileURL = downloadsDirectory.appendingPathComponent(filePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<DownloadedTrack> { $0.songId == songId }
            let tracks = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
            tracks.filter { $0.serverId == serverId }.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.download.debug("DownloadService: remove track save failed — \(error)")
            }
        }
        // Sync DownloadedPlaylist.songIds — remove this songId from any playlist that contains it.
        // Without this, the cold-start retry would re-download the song silently after removal.
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let sid = serverId
            let playlists = (try? context.fetch(
                FetchDescriptor<DownloadedPlaylist>(predicate: #Predicate { $0.serverId == sid })
            )) ?? []
            var didMutate = false
            for playlist in playlists where playlist.songIds.contains(songId) {
                playlist.songIds.removeAll { $0 == songId }
                didMutate = true
            }
            if didMutate {
                do {
                    try context.save()
                } catch {
                    Logger.download.debug("DownloadService: remove playlist sync save failed — \(error)")
                }
            }
        }
    }

    func remove(albumId: String, serverId: UUID) async throws {
        let songIds: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            let all = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
            return all.filter { $0.serverId == serverId && $0.albumId == albumId }.map(\.songId)
        }
        for songId in songIds {
            try? await remove(songId: songId, serverId: serverId)
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
            albums.filter { $0.albumId == albumId && $0.serverId == serverId }.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.download.debug("DownloadService: remove album save failed — \(error)")
            }
        }
    }

    func remove(playlistId: String, serverId: UUID) async throws {
        // Refcount-safe LOCAL purge (mirrors remove(albumId:)): delete the playlist record AND the track files it
        // owns — but KEEP any file still referenced by another downloaded playlist or a downloaded album, so a
        // song shared between two playlists survives until the LAST one is removed. Purely local: never touches
        // the server, so purging an orphan whose playlist is already gone is safe and idempotent.
        let songsToPurge: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            let sid = serverId
            let allPlaylists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
            let mine = allPlaylists.filter { $0.playlistId == playlistId && $0.serverId == sid }
            let owned = Set(mine.flatMap { $0.songIds })
            // Songs still referenced by ANOTHER downloaded playlist on this server → keep their files.
            let sharedByOtherPlaylist = Set(
                allPlaylists.filter { $0.serverId == sid && $0.playlistId != playlistId }.flatMap { $0.songIds }
            )
            // Albums downloaded on this server → keep any of their tracks (don't break a co-downloaded album).
            let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
            let downloadedAlbumIds = Set(albums.filter { $0.serverId == sid }.map(\.albumId))
            let allTracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
            let albumIdBySong = Dictionary(
                allTracks.filter { $0.serverId == sid && owned.contains($0.songId) }
                    .compactMap { track -> (String, String)? in
                        guard let albumId = track.albumId else { return nil }
                        return (track.songId, albumId)
                    },
                uniquingKeysWith: { first, _ in first }
            )
            let toPurge = owned.filter { songId in
                if sharedByOtherPlaylist.contains(songId) { return false }
                if let albumId = albumIdBySong[songId], downloadedAlbumIds.contains(albumId) { return false }
                return true
            }
            // Delete the playlist record FIRST so remove(songId:)'s playlist-sync is a no-op for it.
            mine.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.download.debug("DownloadService: remove playlist save failed — \(error)")
            }
            return Array(toPurge)
        }
        // Delete the files + DownloadedTrack records for the non-shared songs (local + idempotent).
        for songId in songsToPurge {
            try? await remove(songId: songId, serverId: serverId)
        }
    }

    // MARK: - Helpers

    private func taskKey(songId: String, serverId: UUID) -> String {
        "\(songId)::\(serverId.uuidString)"
    }

    private func emit(progress: DownloadProgress) {
        progressContinuation?.yield([progress])
    }

    /// Downloads a cover art image to `coverArtsDirectory/<id>`. No-op if the file already exists.
    /// Throws on network or write error — callers must catch and treat as best-effort.
    private func _downloadCoverArt(id: String) async throws {
        let fileURL = coverArtsDirectory.appendingPathComponent(id)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.download.debug("Cover art '\(id, privacy: .public)' already on disk — skipping.")
            return
        }

        let creds = try await serverService.activeCredentials()
        let client = try await serverService.makeSwiftSonicClient()
        guard let artURL = client.coverArtURL(id: id, size: 600) else {
            throw CassetteError.mediaNotFound(songId: id)
        }

        var request = URLRequest(url: artURL)
        for (k, v) in creds.customHeaders { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await downloadSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            struct HTTPError: Error & Sendable { let statusCode: Int }
            throw CassetteError.downloadFailed(songId: id, underlying: HTTPError(statusCode: code))
        }

        try FileManager.default.createDirectory(at: coverArtsDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        Logger.download.info("Cover art '\(id, privacy: .public)' downloaded (\(data.count) bytes)")
    }
}
