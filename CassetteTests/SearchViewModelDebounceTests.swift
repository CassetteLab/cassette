// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Counting stub

/// Records `search` calls and replays a configurable outcome.
/// Every other endpoint is unused by SearchViewModel and throws.
/// @MainActor (not an actor): the app module compiles with default MainActor
/// isolation, so its unannotated service protocols are MainActor-isolated.
@MainActor
private final class SearchLibraryStub: LibraryServiceProtocol {
    enum Behavior {
        case succeed
        case fail(any Error)
    }

    private(set) var searchCalls: [String] = []
    var behavior: Behavior = .succeed

    func search(_ query: String) async throws -> SearchResult3 {
        searchCalls.append(query)
        switch behavior {
        case .succeed:
            // SearchResult3 is Decodable-only; all fields are optional so "{}" decodes.
            return try JSONDecoder().decode(SearchResult3.self, from: Data("{}".utf8))
        case .fail(let error):
            throw error
        }
    }

    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func getStarred2() async throws -> Starred2 { throw URLError(.unknown) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allAlbums() async throws -> [AlbumID3] { throw URLError(.unknown) }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func randomSongs(size: Int) async throws -> [Song] { throw URLError(.unknown) }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws { throw URLError(.unknown) }
    func getPlayQueue() async throws -> SavedPlayQueue? { throw URLError(.unknown) }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
}

// MARK: - Tests

@Suite("SearchViewModel — debounce & cancellation")
@MainActor
struct SearchViewModelDebounceTests {

    @Test("rapid query changes call the service once, with the final query")
    func rapidTypingCoalescesToFinalQuery() async throws {
        let stub = SearchLibraryStub()
        let vm = SearchViewModel(libraryService: stub)

        // Emulate SwiftUI's .task(id:) contract: each keystroke cancels the
        // previous call. Cancellation lands during the debounce sleep, well
        // within the quiet period — no wall-clock dependence.
        for partial in ["c", "ca", "cas", "cass"] {
            let superseded = Task { await vm.search(query: partial) }
            superseded.cancel()
            await superseded.value
        }
        await vm.search(query: "cassette")

        #expect(stub.searchCalls == ["cassette"])
        #expect(vm.searchError == nil)
        #expect(vm.isSearching == false)
        #expect(vm.searchResults != nil)
    }

    @Test("empty or whitespace query clears state without any request")
    func emptyQueryClearsWithoutRequest() async throws {
        let stub = SearchLibraryStub()
        let vm = SearchViewModel(libraryService: stub)
        vm.searchResults = try JSONDecoder().decode(SearchResult3.self, from: Data("{}".utf8))
        vm.searchError = .unexpected
        vm.isSearching = true

        await vm.search(query: "   ")

        #expect(vm.searchResults == nil)
        #expect(vm.searchError == nil)
        #expect(vm.isSearching == false)
        #expect(stub.searchCalls.isEmpty)
    }

    @Test("superseded in-flight request is swallowed silently")
    func cancelledRequestIsSilent() async throws {
        let cancellations: [any Error] = [
            CancellationError(),
            URLError(.cancelled),
            SwiftSonicError.network(URLError(.cancelled)),
        ]
        for error in cancellations {
            let stub = SearchLibraryStub()
            stub.behavior = .fail(error)
            let vm = SearchViewModel(libraryService: stub)

            await vm.search(query: "cassette")

            #expect(vm.searchError == nil, "\(error) must not surface to the UI")
            #expect(vm.isSearching == false)
        }
    }

    @Test("a real failure still surfaces as a user-facing error")
    func realErrorSurfaces() async throws {
        let stub = SearchLibraryStub()
        stub.behavior = .fail(URLError(.timedOut))
        let vm = SearchViewModel(libraryService: stub)

        await vm.search(query: "cassette")

        #expect(vm.searchError != nil)
        #expect(vm.isSearching == false)
    }
}
