// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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

    nonisolated let progressStream: AsyncStream<[DownloadProgress]>

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer, toastService: ToastService) {
        self.serverService = serverService
        self.modelContainer = modelContainer
        self.toastService = toastService

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
        let filePath: String? = await MainActor.run {
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<DownloadedTrack> { $0.songId == songId }
            let tracks = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
            return tracks.first(where: { $0.serverId == serverId })?.filePath
        }
        guard let filePath else { return nil }
        let url = downloadsDirectory.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.download.warning("Downloaded track record exists but file missing: \(filePath, privacy: .public)")
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
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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

    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let allPlaylists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
            guard let playlist = allPlaylists.first(where: { $0.playlistId == playlistId && $0.serverId == serverId }) else { return nil }
            let allTracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
            let songs = playlist.songIds.compactMap { songId in
                allTracks.first(where: { $0.songId == songId && $0.serverId == serverId })
            }.map { DisplayableSong(from: $0) }
            return LocalPlaylistData(playlistId: playlist.playlistId, name: playlist.name, coverArtId: playlist.coverArtId, songs: songs)
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

        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            struct HTTPError: Error & Sendable { let statusCode: Int }
            throw CassetteError.downloadFailed(songId: song.id, underlying: HTTPError(statusCode: code))
        }

        let mimeType = response.mimeType ?? "audio/mpeg"
        let ext = mimeType.split(separator: "/").last.map(String.init) ?? "mp3"
        let relativePath = "\(serverId.uuidString)/\(song.id).\(ext)"
        let fileURL = downloadsDirectory.appendingPathComponent(relativePath)

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)

        // Capture only Sendable values for the MainActor closure.
        let songId = song.id
        let albumId = song.albumId
        let title = song.title
        let artist = song.artist
        let album = song.album
        let track = song.track
        let duration = song.duration
        let coverArtId = song.coverArt
        let suffix = song.suffix
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

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
                album: album,
                trackNumber: track,
                durationSeconds: duration,
                coverArtId: coverArtId,
                suffix: suffix
            )
            modelContainer.mainContext.insert(record)
            try? modelContainer.mainContext.save()
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
            try? context.save()
        }
        Logger.download.info("Album '\(album.id, privacy: .public)': \(succeeded)/\(total) tracks downloaded.")
        if succeeded == total {
            await toastService.showSuccess("\(album.name) downloaded")
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
            try? context.save()
        }
        Logger.download.info("Playlist '\(playlist.id, privacy: .public)': \(tracksSucceeded)/\(total) tracks downloaded.")
        if tracksSucceeded == totalTracks {
            await toastService.showSuccess("\(playlist.name) downloaded")
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
            try? context.save()
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
            if didMutate { try? context.save() }
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
            try? context.save()
        }
    }

    func remove(playlistId: String, serverId: UUID) async throws {
        // Tracks are shared — removing a playlist record does NOT delete track files.
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
            playlists.filter { $0.playlistId == playlistId && $0.serverId == serverId }.forEach { context.delete($0) }
            try? context.save()
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

        let (data, response) = try await URLSession.shared.data(for: request)
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
