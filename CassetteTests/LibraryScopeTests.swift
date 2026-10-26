// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Cassette

private actor ScopeRecordingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let payload: String
        if request.url?.path.hasSuffix("getArtistInfo2.view") == true {
            payload = #""artistInfo2":{"biography":"Biography"}"#
        } else {
            payload = #""artists":{"index":[{"name":"A","artist":[{"id":"artist","name":"Artist"}]}]}"#
        }
        let data = Data("{\"subsonic-response\":{\"status\":\"ok\",\"version\":\"1.16.1\",\(payload)}}".utf8)
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil
        ))
        return (data, response)
    }

    func scopes() -> [String?] {
        requests.map { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "musicFolderId" }?.value
        }
    }
}

@Suite("LibraryService — library scope changes")
@MainActor
struct LibraryScopeTests {
    private func makeService(transport: ScopeRecordingTransport) throws -> any LibraryServiceProtocol {
        let models = try ModelContainer.cassette(inMemory: true)
        let server = MockServerService()
        let config = ServerConfig(displayName: "Test", baseURL: "https://music.example.com", username: "test")
        config.selectedMusicFolderId = "old"
        server.state.activeServer = ServerSnapshot(from: config)
        server.clientOverride = SwiftSonicClient(
            configuration: ServerConfiguration(serverURL: try #require(URL(string: config.baseURL)),
                                               username: "test", password: "test"),
            transport: transport
        )
        let downloads = DownloadService(serverService: server, modelContainer: models,
                                        toastService: ToastService(), cacheSettings: CacheSettings())
        return LibraryService(serverService: server, modelContainer: models,
                              downloadService: downloads, statsService: StatsService(modelContainer: models))
    }

    @Test("requests use the new scope before the server snapshot is published")
    func seedsScopeBeforePublication() async throws {
        let transport = ScopeRecordingTransport()
        let service = try makeService(transport: transport)
        _ = try await service.artists()
        await service.reloadMusicFolderScope("new")
        _ = try await service.artists()
        await service.reloadMusicFolderScope(nil)
        _ = try await service.artists()

        let scopes = await transport.scopes()
        #expect(scopes == ["old", "new", nil])
    }

    @Test("switching libraries rebuilds the artist name index")
    func clearsArtistNameIndex() async throws {
        let transport = ScopeRecordingTransport()
        let service = try makeService(transport: transport)
        #expect(await service.findArtist(byName: "Artist")?.id == "artist")
        #expect(await service.findArtist(byName: "Artist")?.id == "artist")
        await service.reloadMusicFolderScope("new")
        #expect(await service.findArtist(byName: "Artist")?.id == "artist")

        let scopes = await transport.scopes()
        #expect(scopes == ["old", "new"])
    }

    @Test("switching libraries invalidates cached artist info")
    func clearsArtistInfo() async throws {
        let transport = ScopeRecordingTransport()
        let service = try makeService(transport: transport)
        _ = try await service.getArtistInfo(forArtistID: "artist", count: 20)
        _ = try await service.getArtistInfo(forArtistID: "artist", count: 20)
        await service.reloadMusicFolderScope("new")
        _ = try await service.getArtistInfo(forArtistID: "artist", count: 20)

        let requests = await transport.requests
        #expect(requests.count == 2)
    }
}
