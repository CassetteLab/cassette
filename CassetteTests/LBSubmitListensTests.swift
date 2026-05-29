// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Helpers

actor RecordingTransport: ListenBrainzTransport {
    private(set) var requests: [URLRequest] = []
    private let status: Int
    private let body: Data

    init(status: Int = 200, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, resp)
    }
}

actor SubmitMockKeychain: KeychainServiceProtocol {
    private var storage: [String: Data] = [:]

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) async throws {
        storage[key] = nil
    }
}

private func makeSong() -> DisplayableSong {
    DisplayableSong(
        id: "s1", title: "Paranoid Android", artist: "Radiohead",
        albumId: "alb1", albumName: "OK Computer", artistId: "art1",
        genre: nil, duration: 360, trackNumber: 2, isDownloaded: false,
        coverArtId: nil, audioFormat: nil,
        replayGainTrackGain: nil, replayGainTrackPeak: nil,
        replayGainAlbumGain: nil, replayGainAlbumPeak: nil
    )
}

private let defaultRoot = URL(string: "https://api.listenbrainz.org")!

// Returns a JSON body that makes validateToken succeed; safe to return for submit-listens too
// since sendSubmitListens only checks the status code.
private let validTokenBody = Data(#"{"valid":true,"user_name":"alice"}"#.utf8)

// MARK: - LBTrackMetadata field mapping

@Suite("LBTrackMetadata — field mapping")
struct LBTrackMetadataTests {

    @Test("maps title, artist, albumName from DisplayableSong")
    func fullMapping() {
        let meta = LBTrackMetadata(from: makeSong())
        #expect(meta.trackName == "Paranoid Android")
        #expect(meta.artistName == "Radiohead")
        #expect(meta.releaseName == "OK Computer")
    }

    @Test("uses empty string for artistName when artist is nil")
    func nilArtistBecomesEmptyString() {
        let song = DisplayableSong(
            id: "s", title: "T", artist: nil, albumId: nil, albumName: nil,
            artistId: nil, genre: nil, duration: 300, trackNumber: nil,
            isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil
        )
        let meta = LBTrackMetadata(from: song)
        #expect(meta.artistName == "")
        #expect(meta.releaseName == nil)
    }
}

// MARK: - submitPlayingNow request shape

@Suite("ListenBrainzClient — submitPlayingNow")
struct LBSubmitPlayingNowTests {

    @Test("POST to /1/submit-listens with listen_type playing_now")
    func requestShapeAndListenType() async throws {
        let transport = RecordingTransport(status: 200)
        let client = ListenBrainzClient(transport: transport)
        try await client.submitPlayingNow(track: LBTrackMetadata(from: makeSong()), rootURL: defaultRoot, token: "tok")

        let req = try #require(await transport.requests.first)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path == "/1/submit-listens")

        let dict = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(dict?["listen_type"] as? String == "playing_now")
        let payload = (dict?["payload"] as? [[String: Any]])?.first
        #expect(payload != nil)
        #expect(payload?["listened_at"] == nil)
    }

    @Test("Authorization header carries token")
    func authorizationHeader() async throws {
        let transport = RecordingTransport(status: 200)
        let client = ListenBrainzClient(transport: transport)
        try await client.submitPlayingNow(track: LBTrackMetadata(from: makeSong()), rootURL: defaultRoot, token: "secret_token")

        let req = try #require(await transport.requests.first)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Token secret_token")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("track_metadata fields are snake_case encoded correctly")
    func trackMetadataEncoding() async throws {
        let transport = RecordingTransport(status: 200)
        let client = ListenBrainzClient(transport: transport)
        try await client.submitPlayingNow(track: LBTrackMetadata(from: makeSong()), rootURL: defaultRoot, token: "tok")

        let req = try #require(await transport.requests.first)
        let dict = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        let meta = (dict?["payload"] as? [[String: Any]])?.first?["track_metadata"] as? [String: Any]
        #expect(meta?["track_name"] as? String == "Paranoid Android")
        #expect(meta?["artist_name"] as? String == "Radiohead")
        #expect(meta?["release_name"] as? String == "OK Computer")
    }

    @Test("preserves custom rootURL path for self-hosted instances")
    func customRootURLPathPreserved() async throws {
        let transport = RecordingTransport(status: 200)
        let client = ListenBrainzClient(transport: transport)
        let selfHosted = URL(string: "https://my.server/lb")!
        try await client.submitPlayingNow(track: LBTrackMetadata(from: makeSong()), rootURL: selfHosted, token: "tok")

        let req = try #require(await transport.requests.first)
        #expect(req.url?.absoluteString == "https://my.server/lb/1/submit-listens")
    }
}

// MARK: - submitListen request shape

@Suite("ListenBrainzClient — submitListen")
struct LBSubmitListenTests {

    @Test("POST with listen_type single and listened_at timestamp")
    func requestShapeAndListenType() async throws {
        let transport = RecordingTransport(status: 200)
        let client = ListenBrainzClient(transport: transport)
        try await client.submitListen(
            track: LBTrackMetadata(from: makeSong()),
            listenedAt: 1_700_000_000,
            rootURL: defaultRoot,
            token: "tok"
        )

        let req = try #require(await transport.requests.first)
        let dict = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(dict?["listen_type"] as? String == "single")
        let payload = (dict?["payload"] as? [[String: Any]])?.first
        #expect(payload?["listened_at"] as? Int == 1_700_000_000)
    }

    @Test("release_name is omitted from payload when albumName is nil")
    func releaseNameOmittedWhenNil() async throws {
        let transport = RecordingTransport(status: 200)
        let client = ListenBrainzClient(transport: transport)
        let noAlbumSong = DisplayableSong(
            id: "s", title: "T", artist: "A", albumId: nil, albumName: nil,
            artistId: nil, genre: nil, duration: 300, trackNumber: nil,
            isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil
        )
        try await client.submitListen(
            track: LBTrackMetadata(from: noAlbumSong),
            listenedAt: 1_000,
            rootURL: defaultRoot,
            token: "tok"
        )

        let req = try #require(await transport.requests.first)
        let dict = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        let meta = (dict?["payload"] as? [[String: Any]])?.first?["track_metadata"] as? [String: Any]
        #expect(meta?["release_name"] == nil)
    }
}

// MARK: - Gating: nothing submitted when disabled or no token

@Suite("ListenBrainzService — submission gating")
struct LBSubmissionGatingTests {

    private func makeService(transport: any ListenBrainzTransport) -> (ListenBrainzService, SubmitMockKeychain, UserDefaults) {
        let keychain = SubmitMockKeychain()
        let defaults = UserDefaults(suiteName: "test.submit.\(UUID().uuidString)")!
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
        let service = ListenBrainzService(client: ListenBrainzClient(transport: transport), keychain: keychain, userDefaults: defaults, queueFileURL: tmpURL)
        return (service, keychain, defaults)
    }

    @Test("notifyTrackStarted is a no-op when scrobbling is not configured")
    func notifyNoOpWhenNotConfigured() async {
        let transport = RecordingTransport(status: 200)
        let (service, _, _) = makeService(transport: transport)
        await service.notifyTrackStarted(song: makeSong())
        let count = await transport.requests.count
        #expect(count == 0)
    }

    @Test("notifyScrobbleThreshold is a no-op when scrobbling is not configured")
    func notifyScrobbleNoOpWhenNotConfigured() async {
        let transport = RecordingTransport(status: 200)
        let (service, _, _) = makeService(transport: transport)
        await service.notifyScrobbleThreshold(song: makeSong(), startDate: Date())
        let count = await transport.requests.count
        #expect(count == 0)
    }

    @Test("notifyTrackStarted is a no-op after scrobbling is disabled")
    func notifyNoOpAfterDisable() async throws {
        let transport = RecordingTransport(status: 200, body: validTokenBody)
        let (service, _, _) = makeService(transport: transport)
        try await service.validateAndSaveScrobblingToken("tok", rootURL: defaultRoot)
        await service.disableScrobbling()
        let countBeforeNotify = await transport.requests.count
        await service.notifyTrackStarted(song: makeSong())
        let countAfterNotify = await transport.requests.count
        // Only the validateToken call was made; notifyTrackStarted added nothing.
        #expect(countAfterNotify == countBeforeNotify)
    }

    @Test("notifyTrackStarted submits when scrobbling is enabled and token is present")
    func notifySubmitsWhenEnabled() async throws {
        let transport = RecordingTransport(status: 200, body: validTokenBody)
        let (service, _, _) = makeService(transport: transport)
        try await service.validateAndSaveScrobblingToken("tok", rootURL: defaultRoot)
        await service.notifyTrackStarted(song: makeSong())
        let requests = await transport.requests
        // requests[0] = validateToken, requests[1] = submitPlayingNow
        #expect(requests.count == 2)
        #expect(requests.last?.url?.path.hasSuffix("/1/submit-listens") == true)
    }
}
