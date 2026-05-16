// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

@Suite("StatsService")
struct StatsServiceTests {

    private func makeService() throws -> StatsService {
        let container = try ModelContainer.cassette(inMemory: true)
        return StatsService(modelContainer: container)
    }

    private func makeDTO(
        trackId: String = "track-1",
        trackTitle: String = "Test Track",
        artistName: String = "Test Artist",
        durationListened: TimeInterval = 180,
        trackDuration: TimeInterval = 200,
        wasCompleted: Bool = true,
        serverId: String = "server-A"
    ) -> PlaybackEventDTO {
        PlaybackEventDTO(
            trackId: trackId,
            trackTitle: trackTitle,
            albumId: nil,
            albumTitle: nil,
            artistId: nil,
            artistName: artistName,
            genre: nil,
            timestamp: Date(),
            durationListened: durationListened,
            trackDuration: trackDuration,
            wasCompleted: wasCompleted,
            serverId: serverId
        )
    }

    // MARK: recordPlayback

    @Test func recordPlayback_insertsEvent() async throws {
        let service = try makeService()

        await service.recordPlayback(makeDTO(serverId: "srv-1"))

        let count = await service.eventCount(forServer: "srv-1")
        #expect(count == 1)
    }

    @Test func recordPlayback_multipleEvents_countIncreases() async throws {
        let service = try makeService()

        await service.recordPlayback(makeDTO(trackId: "t1", serverId: "srv-1"))
        await service.recordPlayback(makeDTO(trackId: "t2", serverId: "srv-1"))
        await service.recordPlayback(makeDTO(trackId: "t3", serverId: "srv-1"))

        let count = await service.eventCount(forServer: "srv-1")
        #expect(count == 3)
    }

    // MARK: eventCount

    @Test func eventCount_unknownServer_returnsZero() async throws {
        let service = try makeService()

        let count = await service.eventCount(forServer: "nonexistent")
        #expect(count == 0)
    }

    // MARK: deleteAllEvents

    @Test func deleteAllEvents_clearsTargetServer() async throws {
        let service = try makeService()

        await service.recordPlayback(makeDTO(trackId: "t1", serverId: "srv-A"))
        await service.recordPlayback(makeDTO(trackId: "t2", serverId: "srv-A"))
        await service.recordPlayback(makeDTO(trackId: "t3", serverId: "srv-B"))

        await service.deleteAllEvents(forServer: "srv-A")

        let countA = await service.eventCount(forServer: "srv-A")
        let countB = await service.eventCount(forServer: "srv-B")
        #expect(countA == 0)
        #expect(countB == 1)
    }

    @Test func deleteAllEvents_emptyServer_isNoOp() async throws {
        let service = try makeService()

        await service.deleteAllEvents(forServer: "nonexistent")

        let count = await service.eventCount(forServer: "nonexistent")
        #expect(count == 0)
    }

    // MARK: Multi-server isolation

    @Test func multiServer_eventsAreIsolated() async throws {
        let service = try makeService()

        await service.recordPlayback(makeDTO(trackId: "t1", serverId: "srv-A"))
        await service.recordPlayback(makeDTO(trackId: "t2", serverId: "srv-A"))
        await service.recordPlayback(makeDTO(trackId: "t3", serverId: "srv-B"))
        await service.recordPlayback(makeDTO(trackId: "t4", serverId: "srv-B"))
        await service.recordPlayback(makeDTO(trackId: "t5", serverId: "srv-B"))

        let countA = await service.eventCount(forServer: "srv-A")
        let countB = await service.eventCount(forServer: "srv-B")
        #expect(countA == 2)
        #expect(countB == 3)
    }

    @Test func multiServer_deleteOneDoesNotAffectOther() async throws {
        let service = try makeService()

        await service.recordPlayback(makeDTO(serverId: "srv-A"))
        await service.recordPlayback(makeDTO(serverId: "srv-B"))

        await service.deleteAllEvents(forServer: "srv-A")

        #expect(await service.eventCount(forServer: "srv-A") == 0)
        #expect(await service.eventCount(forServer: "srv-B") == 1)
    }
}
