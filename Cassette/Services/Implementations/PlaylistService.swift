// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

actor PlaylistService: PlaylistServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer
    private let downloadService: DownloadService
    private var cachedClient: SwiftSonicClient?
    private var cachedServerId: UUID?

    private var listCache: [Playlist]?
    private var detailCache: [String: PlaylistWithSongs] = [:]

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer, downloadService: DownloadService) {
        self.serverService = serverService
        self.modelContainer = modelContainer
        self.downloadService = downloadService
    }

    // MARK: - Client

    private func client() async throws -> SwiftSonicClient {
        let activeId = await MainActor.run { serverService.state.activeServer?.id }
        if let cached = cachedClient, cachedServerId == activeId, activeId != nil {
            return cached
        }
        let fresh = try await serverService.makeSwiftSonicClient()
        cachedClient = fresh
        cachedServerId = activeId
        return fresh
    }

    // MARK: - Read

    func listPlaylists() async throws -> [Playlist] {
        if let cached = listCache { return cached }
        let playlists = try await client().getPlaylists()
        listCache = playlists
        return playlists
    }

    func getPlaylist(id: String) async throws -> PlaylistWithSongs {
        if let cached = detailCache[id] { return cached }
        let playlist = try await client().getPlaylist(id: id)
        detailCache[id] = playlist
        return playlist
    }

    // MARK: - Create / Delete

    @discardableResult
    func createPlaylist(name: String, description: String?) async throws -> PlaylistWithSongs {
        let result = try await client().createPlaylist(name: name)
        if let desc = description, !desc.isEmpty {
            try await client().updatePlaylist(id: result.id, comment: desc)
        }
        listCache = nil
        detailCache[result.id] = result
        Logger.playlist.info("Created playlist '\(name, privacy: .private)' id=\(result.id, privacy: .public)")
        return result
    }

    func deletePlaylist(id: String) async throws {
        let previousList = listCache
        let previousDetail = detailCache[id]
        listCache?.removeAll { $0.id == id }
        detailCache[id] = nil
        do {
            try await client().deletePlaylist(id: id)
            Logger.playlist.info("Deleted playlist id=\(id, privacy: .public)")
            // Server delete confirmed → purge any offline download record so Offline keeps no orphan copy
            // ("delete = delete everywhere"). Best-effort (remove logs its own failures internally) and
            // NEVER reached when the server refused — we are past the throwing call — so a refused delete
            // never touches local download state.
            if let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) {
                try? await downloadService.remove(playlistId: id, serverId: serverId)
            }
        } catch {
            listCache = previousList
            detailCache[id] = previousDetail
            throw error
        }
    }

    // MARK: - Metadata updates

    func renamePlaylist(id: String, newName: String) async throws {
        let previousList = listCache
        let previousDetail = detailCache[id]
        if let idx = listCache?.firstIndex(where: { $0.id == id }), let p = listCache?[idx] {
            listCache?[idx] = copying(p, name: newName)
        }
        if let p = detailCache[id] {
            detailCache[id] = copying(p, name: newName)
        }
        do {
            try await client().updatePlaylist(id: id, name: newName)
            Logger.playlist.info("Renamed playlist id=\(id, privacy: .public) to '\(newName, privacy: .private)'")
        } catch {
            listCache = previousList
            detailCache[id] = previousDetail
            throw error
        }
    }

    func updateDescription(id: String, description: String) async throws {
        let previousDetail = detailCache[id]
        if let p = detailCache[id] {
            detailCache[id] = copying(p, comment: description)
        }
        do {
            try await client().updatePlaylist(id: id, comment: description)
            Logger.playlist.info("Updated description for playlist id=\(id, privacy: .public)")
        } catch {
            detailCache[id] = previousDetail
            throw error
        }
    }

    // MARK: - Track mutations

    func addTracks(playlistId: String, songs: [Song]) async throws {
        let previousDetail = detailCache[playlistId]
        let previousList = listCache
        let addedDuration = songs.reduce(0) { $0 + ($1.duration ?? 0) }
        if let p = detailCache[playlistId] {
            detailCache[playlistId] = copying(p,
                songCountDelta: songs.count,
                durationDelta: addedDuration,
                entry: (p.entry ?? []) + songs
            )
        }
        if let idx = listCache?.firstIndex(where: { $0.id == playlistId }), let p = listCache?[idx] {
            listCache?[idx] = copying(p, songCountDelta: songs.count, durationDelta: addedDuration)
        }
        do {
            try await client().updatePlaylist(id: playlistId, songIdsToAdd: songs.map(\.id))
            Logger.playlist.info("Added \(songs.count, privacy: .public) track(s) to playlist id=\(playlistId, privacy: .public)")
            await syncDownloadedPlaylistAfterAdd(playlistId: playlistId, addedSongs: songs)
        } catch {
            detailCache[playlistId] = previousDetail
            listCache = previousList
            throw error
        }
    }

    func removeTracks(playlistId: String, indices: [Int]) async throws {
        let previousDetail = detailCache[playlistId]
        let previousList = listCache
        let indexSet = Set(indices)
        let removedSongIds: [String] = {
            guard let entry = detailCache[playlistId]?.entry else { return [] }
            return indices.compactMap { idx in idx < entry.count ? entry[idx].id : nil }
        }()
        if let p = detailCache[playlistId], let entry = p.entry {
            let removedDuration = indexSet.reduce(0) { sum, idx in
                sum + (idx < entry.count ? entry[idx].duration ?? 0 : 0)
            }
            let newEntry = entry.enumerated().filter { !indexSet.contains($0.offset) }.map(\.element)
            detailCache[playlistId] = copying(p,
                songCountDelta: -indexSet.count,
                durationDelta: -removedDuration,
                entry: newEntry
            )
            if let idx = listCache?.firstIndex(where: { $0.id == playlistId }), let lp = listCache?[idx] {
                listCache?[idx] = copying(lp, songCountDelta: -indexSet.count, durationDelta: -removedDuration)
            }
        }
        do {
            try await client().updatePlaylist(id: playlistId, songIndexesToRemove: indices)
            Logger.playlist.info("Removed \(indices.count, privacy: .public) track(s) from playlist id=\(playlistId, privacy: .public)")
            await syncDownloadedPlaylistAfterRemove(playlistId: playlistId, removedSongIds: removedSongIds)
        } catch {
            detailCache[playlistId] = previousDetail
            listCache = previousList
            throw error
        }
    }

    func reorderTracks(playlistId: String, orderedSongIds: [String]) async throws {
        let previousDetail = detailCache[playlistId]
        if let p = detailCache[playlistId], let entry = p.entry {
            let songById = Dictionary(entry.map { ($0.id, $0) }, uniquingKeysWith: { f, _ in f })
            let reordered = orderedSongIds.compactMap { songById[$0] }
            detailCache[playlistId] = copying(p, entry: reordered)
        }
        do {
            try await client().createPlaylist(playlistId: playlistId, songIds: orderedSongIds)
            Logger.playlist.info("Reordered tracks in playlist id=\(playlistId, privacy: .public)")
        } catch {
            detailCache[playlistId] = previousDetail
            throw error
        }
    }

    // MARK: - Offline sync

    private func syncDownloadedPlaylistAfterAdd(playlistId: String, addedSongs: [Song]) async {
        let serverId: UUID? = await MainActor.run { () -> UUID? in
            let context = modelContainer.mainContext
            let pid = playlistId
            let descriptor = FetchDescriptor<DownloadedPlaylist>(
                predicate: #Predicate { $0.playlistId == pid }
            )
            guard let record = try? context.fetch(descriptor).first else { return nil }
            record.songIds.append(contentsOf: addedSongs.map(\.id))
            try? context.save()
            return record.serverId
        }
        guard let serverId else { return }
        for song in addedSongs {
            Task { [weak self] in
                try? await self?.downloadService.download(song: song, serverId: serverId)
            }
        }
    }

    private func syncDownloadedPlaylistAfterRemove(playlistId: String, removedSongIds: [String]) async {
        guard !removedSongIds.isEmpty else { return }
        await MainActor.run {
            let context = modelContainer.mainContext
            let pid = playlistId
            let descriptor = FetchDescriptor<DownloadedPlaylist>(
                predicate: #Predicate { $0.playlistId == pid }
            )
            guard let record = try? context.fetch(descriptor).first else { return }
            let removedSet = Set(removedSongIds)
            record.songIds.removeAll { removedSet.contains($0) }
            try? context.save()
        }
    }

    func retryMissingPlaylistDownloads() async {
        let records = await MainActor.run { () -> [(playlistId: String, serverId: UUID, songIds: [String])] in
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<DownloadedPlaylist>()
            guard let fetched = try? context.fetch(descriptor) else { return [] }
            return fetched
                .filter { !$0.songIds.isEmpty }
                .map { (playlistId: $0.playlistId, serverId: $0.serverId, songIds: $0.songIds) }
        }
        guard !records.isEmpty else { return }

        for record in records {
            let downloadedIds = await downloadService.downloadedSongIds(serverId: record.serverId)
            let missingIds = record.songIds.filter { !downloadedIds.contains($0) }

            guard !missingIds.isEmpty else { continue }

            Logger.playlist.info("Retrying \(missingIds.count, privacy: .public) missing track(s) for playlist '\(record.playlistId, privacy: .public)'")

            guard let playlist = try? await client().getPlaylist(id: record.playlistId) else {
                Logger.playlist.warning("Failed to fetch playlist '\(record.playlistId, privacy: .public)' for retry — skipping.")
                continue
            }

            let missingIdSet = Set(missingIds)
            let songsToDownload = (playlist.entry ?? []).filter { missingIdSet.contains($0.id) }
            let serverId = record.serverId

            for song in songsToDownload {
                Task { [weak self] in
                    try? await self?.downloadService.download(song: song, serverId: serverId)
                }
            }
        }
    }

    // MARK: - Copy helpers

    private func copying(
        _ p: Playlist,
        name: String? = nil,
        comment: String? = nil,
        songCountDelta: Int = 0,
        durationDelta: Int = 0
    ) -> Playlist {
        Playlist(
            id: p.id,
            name: name ?? p.name,
            songCount: max(0, p.songCount + songCountDelta),
            duration: max(0, p.duration + durationDelta),
            comment: comment ?? p.comment,
            owner: p.owner,
            isPublic: p.isPublic,
            created: p.created,
            changed: p.changed,
            coverArt: p.coverArt
        )
    }

    private func copying(
        _ p: PlaylistWithSongs,
        name: String? = nil,
        comment: String? = nil,
        songCountDelta: Int = 0,
        durationDelta: Int = 0,
        entry: [Song]? = nil
    ) -> PlaylistWithSongs {
        PlaylistWithSongs(
            id: p.id,
            name: name ?? p.name,
            songCount: max(0, p.songCount + songCountDelta),
            duration: max(0, p.duration + durationDelta),
            comment: comment ?? p.comment,
            owner: p.owner,
            isPublic: p.isPublic,
            created: p.created,
            changed: p.changed,
            coverArt: p.coverArt,
            entry: entry ?? p.entry
        )
    }
}
