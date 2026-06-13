// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

/// Exercises the REAL `DownloadService.localPlaylistData` reconstruction against a real
/// in-memory SwiftData store — not a hand-built `LocalPlaylistData` stub. This is the layer
/// the throw-only ViewModel tests never touched, where the offline-playlist bug actually lived.
@Suite("Offline downloads — real localPlaylistData round-trip")
@MainActor
struct OfflineDownloadRoundTripTests {

    private func makeService() throws -> (service: DownloadService, container: ModelContainer, serverId: UUID) {
        let container = try ModelContainer.cassette(inMemory: true)
        let service = DownloadService(
            serverService: MockServerService(),
            modelContainer: container,
            toastService: ToastService()
        )
        return (service, container, UUID())
    }

    private func insertTrack(_ container: ModelContainer, songId: String, serverId: UUID, track: Int) {
        container.mainContext.insert(
            DownloadedTrack(
                songId: songId,
                serverId: serverId,
                albumId: "album-1",
                filePath: "\(serverId.uuidString)/\(songId).mp3",
                fileSize: 1234,
                mimeType: "audio/mpeg",
                title: "Track \(songId)",
                artist: "Artist",
                album: "Album",
                trackNumber: track
            )
        )
    }

    @Test("real localPlaylistData reconstructs tracks in stored playlist order")
    func reconstructsInOrder() async throws {
        let (service, container, sid) = try makeService()
        // Insert out of order on purpose; songIds defines the order, not insertion/track number.
        insertTrack(container, songId: "s2", serverId: sid, track: 2)
        insertTrack(container, songId: "s1", serverId: sid, track: 1)
        container.mainContext.insert(
            DownloadedPlaylist(
                playlistId: "pl-1", serverId: sid, name: "Road Trip",
                tracksCount: 2, totalTracksCount: 2, songIds: ["s1", "s2"]
            )
        )
        try container.mainContext.save()

        let data = await service.localPlaylistData(playlistId: "pl-1", serverId: sid)
        #expect(data?.songs.map(\.id) == ["s1", "s2"])
        #expect(data?.name == "Road Trip")
    }

    @Test("localPlaylistData returns nil when there is no downloaded playlist record")
    func nilWhenNoRecord() async throws {
        let (service, _, sid) = try makeService()
        let data = await service.localPlaylistData(playlistId: "missing", serverId: sid)
        #expect(data == nil)
    }

    @Test("localPlaylistData ignores tracks from a different server")
    func ignoresOtherServerTracks() async throws {
        let (service, container, sid) = try makeService()
        let otherServer = UUID()
        insertTrack(container, songId: "s1", serverId: sid, track: 1)
        insertTrack(container, songId: "s2", serverId: otherServer, track: 2) // wrong server
        container.mainContext.insert(
            DownloadedPlaylist(
                playlistId: "pl-1", serverId: sid, name: "Road Trip",
                tracksCount: 2, totalTracksCount: 2, songIds: ["s1", "s2"]
            )
        )
        try container.mainContext.save()

        let data = await service.localPlaylistData(playlistId: "pl-1", serverId: sid)
        #expect(data?.songs.map(\.id) == ["s1"]) // s2 belongs to another server, dropped
    }

    @Test("backfillPlaylistSongIds repairs an empty songIds from on-disk tracks, in order")
    func backfillRepairsEmptySongIds() async throws {
        let (service, container, sid) = try makeService()
        insertTrack(container, songId: "s1", serverId: sid, track: 1)
        insertTrack(container, songId: "s2", serverId: sid, track: 2)
        container.mainContext.insert(
            DownloadedPlaylist(
                playlistId: "pl-1", serverId: sid, name: "Road Trip",
                tracksCount: 2, totalTracksCount: 2, songIds: [] // pre-migration record
            )
        )
        try container.mainContext.save()

        // Empty songIds → nothing reconstructs yet.
        let before = await service.localPlaylistData(playlistId: "pl-1", serverId: sid)
        #expect(before?.songs.isEmpty == true)

        // Repair from authoritative order; "s3" isn't downloaded and must be dropped.
        await service.backfillPlaylistSongIds(
            playlistId: "pl-1", serverId: sid, orderedSongIds: ["s2", "s1", "s3"]
        )

        let after = await service.localPlaylistData(playlistId: "pl-1", serverId: sid)
        #expect(after?.songs.map(\.id) == ["s2", "s1"])
    }

    @Test("backfillPlaylistSongIds does not overwrite an already-populated songIds")
    func backfillLeavesPopulatedAlone() async throws {
        let (service, container, sid) = try makeService()
        insertTrack(container, songId: "s1", serverId: sid, track: 1)
        insertTrack(container, songId: "s2", serverId: sid, track: 2)
        container.mainContext.insert(
            DownloadedPlaylist(
                playlistId: "pl-1", serverId: sid, name: "Road Trip",
                tracksCount: 2, totalTracksCount: 2, songIds: ["s1", "s2"]
            )
        )
        try container.mainContext.save()

        await service.backfillPlaylistSongIds(
            playlistId: "pl-1", serverId: sid, orderedSongIds: ["s2", "s1"]
        )

        let data = await service.localPlaylistData(playlistId: "pl-1", serverId: sid)
        #expect(data?.songs.map(\.id) == ["s1", "s2"]) // unchanged
    }
}
