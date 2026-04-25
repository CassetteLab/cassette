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

    nonisolated let progressStream: AsyncStream<[DownloadProgress]>

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer) {
        self.serverService = serverService
        self.modelContainer = modelContainer

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
            let allAlbums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
            guard let album = allAlbums.first(where: { $0.albumId == albumId && $0.serverId == serverId }) else { return nil }
            let allTracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
            let songs = allTracks
                .filter { $0.albumId == albumId && $0.serverId == serverId }
                .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                .map { DisplayableSong(from: $0) }
            return LocalAlbumData(albumId: album.albumId, albumName: album.name, artistName: album.artist, coverArtId: album.coverArtId, songs: songs)
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

        let (data, response) = try await URLSession.shared.data(for: request)

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
        try data.write(to: fileURL, options: .atomic)

        // Capture only Sendable values for the MainActor closure.
        let songId = song.id
        let albumId = song.albumId
        let title = song.title
        let artist = song.artist
        let album = song.album
        let track = song.track
        let duration = song.duration
        let coverArtId = song.coverArt
        let fileSize = Int64(data.count)

        await MainActor.run {
            let context = ModelContext(modelContainer)
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
                coverArtId: coverArtId
            )
            context.insert(record)
            try? context.save()
        }

        emit(progress: DownloadProgress(songId: song.id, serverId: serverId, progress: 1.0, totalBytes: fileSize, receivedBytes: fileSize))
        Logger.download.info("Downloaded '\(song.id, privacy: .public)' (\(data.count) bytes)")
    }

    // MARK: - Album download

    func download(album: AlbumID3, serverId: UUID) async throws {
        guard let songs = album.song else { return }
        let total = songs.count
        var succeeded = 0

        for song in songs {
            do {
                try await download(song: song, serverId: serverId)
                succeeded += 1
            } catch {
                Logger.download.error("Failed song '\(song.id, privacy: .public)' in album '\(album.id, privacy: .public)': \(error, privacy: .public)")
            }
        }

        let albumId = album.id
        let albumName = album.name
        let albumArtist = album.artist
        let coverArt = album.coverArt
        let tracksSucceeded = succeeded
        let totalTracks = total

        await MainActor.run {
            let context = ModelContext(modelContainer)
            let existing = (try? context.fetch(FetchDescriptor<DownloadedAlbum>()))?
                .first(where: { $0.albumId == albumId && $0.serverId == serverId })

            if let existing {
                existing.tracksCount = tracksSucceeded
                existing.totalTracksCount = totalTracks
                existing.downloadedAt = Date()
            } else {
                let record = DownloadedAlbum(
                    albumId: albumId,
                    serverId: serverId,
                    name: albumName,
                    artist: albumArtist,
                    tracksCount: tracksSucceeded,
                    totalTracksCount: totalTracks,
                    coverArtId: coverArt
                )
                context.insert(record)
            }
            try? context.save()
        }
        Logger.download.info("Album '\(album.id, privacy: .public)': \(succeeded)/\(total) tracks downloaded.")
    }

    // MARK: - Playlist download

    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws {
        let songs = playlist.entry ?? []
        let total = songs.count
        var succeededIds: [String] = []

        for song in songs {
            do {
                try await download(song: song, serverId: serverId)
                succeededIds.append(song.id)
            } catch {
                Logger.download.error("Failed song '\(song.id, privacy: .public)' in playlist '\(playlist.id, privacy: .public)': \(error, privacy: .public)")
            }
        }

        let playlistId = playlist.id
        let playlistName = playlist.name
        let comment = playlist.comment
        let coverArt = playlist.coverArt
        let tracksSucceeded = succeededIds.count
        let totalTracks = total
        let ids = succeededIds

        await MainActor.run {
            let context = ModelContext(modelContainer)
            let existing = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>()))?
                .first(where: { $0.playlistId == playlistId && $0.serverId == serverId })

            if let existing {
                existing.tracksCount = tracksSucceeded
                existing.totalTracksCount = totalTracks
                existing.downloadedAt = Date()
                existing.songIds = ids
            } else {
                let record = DownloadedPlaylist(
                    playlistId: playlistId,
                    serverId: serverId,
                    name: playlistName,
                    comment: comment,
                    tracksCount: tracksSucceeded,
                    totalTracksCount: totalTracks,
                    coverArtId: coverArt,
                    songIds: ids
                )
                context.insert(record)
            }
            try? context.save()
        }
        Logger.download.info("Playlist '\(playlist.id, privacy: .public)': \(tracksSucceeded)/\(total) tracks downloaded.")
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
}
