// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Mock provider

private struct DVMockProvider: RecommendationProvider {
    let releases: [AlbumRecommendation]
    let shouldThrow: Bool

    init(releases: [AlbumRecommendation] = [], shouldThrow: Bool = false) {
        self.releases = releases
        self.shouldThrow = shouldThrow
    }

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return Array(releases.prefix(limit))
    }

    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] { [] }
}

// MARK: - Capturing provider (records params for assertion)

private actor DVCapturingProvider: RecommendationProvider {
    private(set) var capturedLimit: Int?
    private(set) var capturedDaysWindow: Int?

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        capturedLimit = limit
        capturedDaysWindow = daysWindow
        return []
    }
}

// MARK: - Library stub (never called in fresh releases tests)

private actor DVLibraryStub: LibraryServiceProtocol {
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func search(_ query: String) async throws -> SearchResult3 { throw URLError(.unknown) }
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

@Suite("DiscoverViewModel — fresh releases")
@MainActor
struct DiscoverViewModelFreshReleasesTests {

    private func makeVM(releases: [AlbumRecommendation] = [], shouldThrow: Bool = false) -> DiscoverViewModel {
        let provider = DVMockProvider(releases: releases, shouldThrow: shouldThrow)
        let service = RecommendationService(providers: [provider])
        return DiscoverViewModel(libraryService: DVLibraryStub(), recommendationService: service)
    }

    @Test("happy path: provider results are stored in freshReleases")
    func happyPath() async {
        let releases = [
            AlbumRecommendation(id: "mbid-1", title: "Test Album", artistName: "Test Artist",
                                releaseDate: nil, coverArtURL: nil, inLibrary: false)
        ]
        let vm = makeVM(releases: releases)
        await vm.loadFreshReleases()
        #expect(vm.freshReleases == releases)
    }

    @Test("empty provider: freshReleases stays empty")
    func emptyProvider() async {
        let vm = makeVM(releases: [])
        await vm.loadFreshReleases()
        #expect(vm.freshReleases.isEmpty)
    }

    @Test("throwing provider: no rethrow, freshReleases stays empty")
    func throwingProviderNoRethrow() async {
        let vm = makeVM(shouldThrow: true)
        await vm.loadFreshReleases()
        #expect(vm.freshReleases.isEmpty)
    }

    @Test("isLoadingFreshReleases starts false and resets to false after load")
    func loadingFlagResets() async {
        let vm = makeVM()
        #expect(!vm.isLoadingFreshReleases)
        await vm.loadFreshReleases()
        #expect(!vm.isLoadingFreshReleases)
    }

    @Test("limit: VM requests at most 10 releases from the service")
    func limitCappedAt10() async {
        let manyReleases = (0..<30).map {
            AlbumRecommendation(id: "id-\($0)", title: "Album \($0)", artistName: "Artist",
                                releaseDate: nil, coverArtURL: nil, inLibrary: false)
        }
        let vm = makeVM(releases: manyReleases)
        await vm.loadFreshReleases()
        #expect(vm.freshReleases.count == 10)
    }

    @Test("VM requests freshReleases with limit=10 and daysWindow=7")
    func requestsCorrectLimitAndWindow() async {
        let capturing = DVCapturingProvider()
        let service = RecommendationService(providers: [capturing])
        let vm = DiscoverViewModel(libraryService: DVLibraryStub(), recommendationService: service)
        await vm.loadFreshReleases()
        let limit = await capturing.capturedLimit
        let window = await capturing.capturedDaysWindow
        #expect(limit == 10)
        #expect(window == 7)
    }

    @Test("releases sorted by releaseDate descending after load")
    func sortedByDateDescending() async {
        let cal = Calendar.current
        let may10 = cal.date(from: DateComponents(year: 2026, month: 5, day: 10)) ?? Date()
        let may1  = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))  ?? Date()
        let may20 = cal.date(from: DateComponents(year: 2026, month: 5, day: 20)) ?? Date()
        let releases = [
            AlbumRecommendation(id: "a", title: "A", artistName: "X", releaseDate: may10, coverArtURL: nil, inLibrary: false),
            AlbumRecommendation(id: "b", title: "B", artistName: "X", releaseDate: may1,  coverArtURL: nil, inLibrary: false),
            AlbumRecommendation(id: "c", title: "C", artistName: "X", releaseDate: may20, coverArtURL: nil, inLibrary: false),
        ]
        let vm = makeVM(releases: releases)
        await vm.loadFreshReleases()
        let ids = vm.freshReleases.compactMap { $0.id }
        #expect(ids == ["c", "a", "b"], "Expected newest first: c(may-20), a(may-10), b(may-1)")
    }
}
