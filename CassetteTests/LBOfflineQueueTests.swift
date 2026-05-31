// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Test helpers

/// Transport whose responses are consumed in declaration order.
/// Remaining calls after the list is exhausted fall back to `fallbackStatus`.
private actor ProgrammableTransport: ListenBrainzTransport {
    private var scheduled: [(status: Int, body: Data)]
    private(set) var requests: [URLRequest] = []
    let fallbackStatus: Int

    init(_ responses: [(Int, Data)] = [], fallback: Int = 200) {
        self.scheduled = responses.map { (status: $0.0, body: $0.1) }
        self.fallbackStatus = fallback
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = scheduled.isEmpty ? (fallbackStatus, Data()) : scheduled.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, resp)
    }
}

private let validTokenBody = Data(#"{"valid":true,"user_name":"alice"}"#.utf8)
private let defaultRoot = URL(string: "https://api.listenbrainz.org")!

private func tempQueueURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
}

private func makeSong(duration: TimeInterval = 300) -> DisplayableSong {
    DisplayableSong(
        id: "s1", title: "Motion Picture Soundtrack", artist: "Radiohead",
        albumId: "alb1", albumName: "Kid A", artistId: "art1",
        genre: nil, duration: duration, trackNumber: 10, isDownloaded: false,
        coverArtId: nil, audioFormat: nil,
        replayGainTrackGain: nil, replayGainTrackPeak: nil,
        replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
        replayGainBaseGain: nil, replayGainFallbackGain: nil
    )
}

/// Creates a service pre-configured with a valid scrobbling token using `transport` for
/// the validateToken call, then returns the service (backed by `submitTransport` afterwards).
private func configuredService(
    validateTransport: any ListenBrainzTransport,
    queueFileURL: URL
) async throws -> ListenBrainzService {
    let keychain = SubmitMockKeychain()
    let defaults = UserDefaults(suiteName: "test.queue.\(UUID().uuidString)")!
    let service = ListenBrainzService(
        client: ListenBrainzClient(transport: validateTransport),
        keychain: keychain,
        userDefaults: defaults,
        queueFileURL: queueFileURL
    )
    try await service.validateAndSaveScrobblingToken("tok", rootURL: defaultRoot)
    return service
}

// MARK: - PendingListen — Codable round-trip

@Suite("PendingListen — Codable round-trip")
struct PendingListenCodableTests {

    @Test("all fields survive encode → decode")
    func roundTrip_allFields() throws {
        let original = PendingListen(
            listenedAt: 1_700_000_000,
            trackName: "Motion Picture Soundtrack",
            artistName: "Radiohead",
            releaseName: "Kid A",
            durationMs: 154_000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingListen.self, from: data)
        #expect(decoded == original)
    }

    @Test("nil optional fields survive encode → decode")
    func roundTrip_nilOptionals() throws {
        let original = PendingListen(
            listenedAt: 1_000,
            trackName: "T",
            artistName: "A",
            releaseName: nil,
            durationMs: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingListen.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - Queue file persistence

@Suite("Queue file persistence")
struct QueueFileTests {

    @Test("queue survives service restart — written by one instance, read by another")
    func queueRoundTripAcrossInstances() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // instance 1: configure + trigger an enqueue
        let t1 = ProgrammableTransport([(200, validTokenBody)], fallback: 503)
        let s1 = try await configuredService(validateTransport: t1, queueFileURL: fileURL)
        await s1.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        let countAfterEnqueue = await s1.pendingListenCount
        #expect(countAfterEnqueue == 1)

        // instance 2: fresh service, same keychain/defaults path → load queue → flush fails
        // (fallback 503 prevents auto-flush from clearing the count)
        let t2 = ProgrammableTransport(fallback: 503)
        let keychain = SubmitMockKeychain()
        let defaults = UserDefaults(suiteName: "test.queue.\(UUID().uuidString)")!
        // manually store the scrobbling config so loadPersistedState sets hasScrobblingToken
        try await keychain.store("tok", forKey: "app.cassette.listenbrainz.token")
        try await keychain.store("alice", forKey: "app.cassette.listenbrainz.username")
        defaults.set(true, forKey: "app.cassette.listenbrainz.scrobbling.isEnabled")
        let s2 = ListenBrainzService(
            client: ListenBrainzClient(transport: t2),
            keychain: keychain,
            userDefaults: defaults,
            queueFileURL: fileURL
        )
        await s2.loadPersistedState()
        let countAfterLoad = await s2.pendingListenCount
        #expect(countAfterLoad == 1)
    }

    @Test("corrupt queue file starts empty without crashing")
    func corruptFileStartsEmpty() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "not valid json [ {".data(using: .utf8)!.write(to: fileURL)

        let keychain = SubmitMockKeychain()
        let defaults = UserDefaults(suiteName: "test.queue.\(UUID().uuidString)")!
        let service = ListenBrainzService(
            client: ListenBrainzClient(transport: ProgrammableTransport()),
            keychain: keychain,
            userDefaults: defaults,
            queueFileURL: fileURL
        )
        await service.loadPersistedState()
        let count = await service.pendingListenCount
        #expect(count == 0)
    }
}

// MARK: - Queue enqueue behaviour

@Suite("Queue enqueue behaviour")
struct QueueEnqueueTests {

    @Test("transient 5xx error enqueues the listen")
    func transient5xxEnqueues() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody)], fallback: 503)
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        let count = await service.pendingListenCount
        #expect(count == 1)
    }

    @Test("permanent 401 is dropped — not enqueued")
    func permanent401NotEnqueued() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody)], fallback: 401)
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        let count = await service.pendingListenCount
        #expect(count == 0)
    }

    @Test("permanent 4xx client error is dropped — not enqueued")
    func permanent4xxNotEnqueued() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody)], fallback: 400)
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        let count = await service.pendingListenCount
        #expect(count == 0)
    }

    @Test("playing_now failure is always dropped — never enqueued")
    func playingNowFailureNeverEnqueues() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody)], fallback: 503)
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyTrackStarted(song: makeSong())
        let count = await service.pendingListenCount
        #expect(count == 0)
    }

    @Test("no enqueue when scrobbling is disabled")
    func noEnqueueWhenDisabled() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody)], fallback: 503)
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.disableScrobbling()
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        let count = await service.pendingListenCount
        #expect(count == 0)
    }
}

// MARK: - Queue flush behaviour

@Suite("Queue flush behaviour")
struct QueueFlushTests {

    @Test("flush POSTs listen_type import with correct listened_at values")
    func flushBuildsImportPayload() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_100)
        // validateToken → 200; submitListen × 2 → 503 (enqueue); submitImport → 200 (flush)
        let transport = ProgrammableTransport([
            (200, validTokenBody),
            (503, Data()),
            (503, Data()),
            (200, Data()),
        ])
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: t1)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: t2)
        #expect(await service.pendingListenCount == 2)

        await service.flushOfflineQueue()
        #expect(await service.pendingListenCount == 0)

        let reqs = await transport.requests
        let flushReq = try #require(reqs.last)
        let body = try JSONSerialization.jsonObject(with: flushReq.httpBody ?? Data()) as? [String: Any]
        #expect(body?["listen_type"] as? String == "import")
        let payload = body?["payload"] as? [[String: Any]]
        #expect(payload?.count == 2)
        #expect((payload?[0])?["listened_at"] as? Int == Int(t1.timeIntervalSince1970))
        #expect((payload?[1])?["listened_at"] as? Int == Int(t2.timeIntervalSince1970))
    }

    @Test("flush includes submission_client and media_player in additional_info")
    func flushAdditionalInfo() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([
            (200, validTokenBody),
            (503, Data()),
            (200, Data()),
        ])
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(duration: 154), startDate: Date())
        await service.flushOfflineQueue()

        let reqs = await transport.requests
        let body = try JSONSerialization.jsonObject(with: reqs.last?.httpBody ?? Data()) as? [String: Any]
        let meta = (body?["payload"] as? [[String: Any]])?.first?["track_metadata"] as? [String: Any]
        let info = meta?["additional_info"] as? [String: Any]
        #expect(info?["submission_client"] as? String == "Cassette")
        #expect(info?["media_player"] as? String == "Cassette")
        #expect(info?["duration_ms"] as? Int == 154_000)
    }

    @Test("queue is cleared after a successful flush")
    func queueClearedOn200() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody), (503, Data()), (200, Data())])
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        #expect(await service.pendingListenCount == 1)
        await service.flushOfflineQueue()
        #expect(await service.pendingListenCount == 0)
    }

    @Test("queue is retained when flush fails")
    func queueRetainedOnFailure() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody), (503, Data())], fallback: 503)
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        await service.flushOfflineQueue()
        let count = await service.pendingListenCount
        #expect(count == 1)
    }

    @Test("flush is a no-op when queue is empty — no HTTP request sent")
    func noOpWhenEmpty() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody)])
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.flushOfflineQueue()
        let reqs = await transport.requests
        // Only the validateToken call should exist; no submitImport request.
        #expect(reqs.count == 1)
    }

    @Test("flush is gated when scrobbling is disabled after items are queued")
    func noFlushWhenDisabled() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody), (503, Data())])
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        await service.disableScrobbling()
        await service.flushOfflineQueue()
        // Queue unchanged — flush was gated; no submitImport request made.
        let count = await service.pendingListenCount
        #expect(count == 1)
        let reqCount = await transport.requests.count
        #expect(reqCount == 2)  // validateToken + failed submitListen
    }
}

// MARK: - clearScrobblingToken clears queue

@Suite("clearScrobblingToken clears queue")
struct ClearTokenQueueTests {

    @Test("queue is emptied and file is removed after clearScrobblingToken")
    func clearTokenClearsQueue() async throws {
        let fileURL = tempQueueURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ProgrammableTransport([(200, validTokenBody), (503, Data())])
        let service = try await configuredService(validateTransport: transport, queueFileURL: fileURL)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        #expect(await service.pendingListenCount == 1)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        await service.clearScrobblingToken()
        #expect(await service.pendingListenCount == 0)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
