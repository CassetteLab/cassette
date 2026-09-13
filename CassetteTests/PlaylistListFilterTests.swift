// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

/// Only `playlists()` and `getStarred2()` are reachable from the playlist list; every other
/// endpoint throws. @MainActor rather than an actor: the app module compiles with default MainActor
/// isolation, so its unannotated service protocols are MainActor-isolated.
@MainActor
private final class LibraryStub: LibraryServiceProtocol {
    private let served: [Playlist]
    private let starred: Starred2

    init(playlists: [Playlist], starred: Starred2) {
        self.served = playlists
        self.starred = starred
    }

    func playlists() async throws -> [Playlist] { served }
    func getStarred2() async throws -> Starred2 { starred }

    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func search(_ query: String) async throws -> SearchResult3 { throw URLError(.unknown) }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allAlbums() async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allSongs(offset: Int, count: Int) async throws -> [Song] { [] }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func randomSongs(size: Int) async throws -> [Song] { throw URLError(.unknown) }
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] { [] }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws { throw URLError(.unknown) }
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
}

private nonisolated func playlist(_ id: String, _ name: String) -> Playlist {
    Playlist(id: id, name: name, songCount: 12, duration: 2400)
}

/// SwiftSonic's starred models are Decodable-only from outside the package, so they are built from
/// JSON rather than a memberwise init.
private func starredFixture(artist: String, count: Int = ArtistBestOf.minimumSongs) throws -> Starred2 {
    let songs = (0..<count).map { index in
        #"{"id":"\#(artist)-\#(index)","title":"Track \#(index)","artist":"\#(artist)","artistId":"id-\#(artist)"}"#
    }
    let json = #"{"song":["# + songs.joined(separator: ",") + "]}"
    return try JSONDecoder().decode(Starred2.self, from: Data(json.utf8))
}

/// Two generated moods, one Wrapped, two of the user's own. Outside the suite because default
/// arguments are evaluated in a nonisolated context, which a MainActor-isolated static is not.
private nonisolated func libraryFixture() -> [Playlist] {
    [
        playlist("m1", "Cassette · Night"),
        playlist("m2", "Cassette · Workout"),
        playlist("w1", "Cassette Wrapped 2025"),
        playlist("u1", "Road trip"),
        playlist("u2", "Sunday morning")
    ]
}

private func noStarsFixture() throws -> Starred2 {
    try JSONDecoder().decode(Starred2.self, from: Data("{}".utf8))
}

@Suite("Playlist list filtering")
@MainActor
struct PlaylistListFilterTests {

    private func loadedViewModel(
        playlists: [Playlist] = libraryFixture(),
        starred: Starred2? = nil
    ) async throws -> PlaylistListViewModel {
        let stars = try starred ?? starredFixture(artist: "Radiohead")
        let vm = PlaylistListViewModel(libraryService: LibraryStub(playlists: playlists, starred: stars))
        await vm.load()
        await vm.loadBestOf()
        return vm
    }

    // MARK: - Non-regression

    @Test("An untouched filter shows exactly what was fetched")
    func defaultShowsEverything() async throws {
        let vm = try await loadedViewModel()
        #expect(vm.visiblePlaylists.map(\.id) == libraryFixture().map(\.id))
        #expect(vm.visibleBestOfPlaylists.count == vm.bestOfPlaylists.count)
        #expect(!vm.isFiltering)
        #expect(!vm.isEmptyBecauseFiltered)
    }

    @Test("An empty library is empty on its own account, not because of the filter")
    func emptyLibraryIsNotAFilteredEmpty() async throws {
        let vm = try await loadedViewModel(playlists: [], starred: noStarsFixture())
        #expect(!vm.isEmptyBecauseFiltered)
    }

    // MARK: - Each kind, independently

    @Test("Hiding the moods leaves Wrapped and the user's own playlists")
    func hideMoods() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: [.moods], classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visiblePlaylists.map(\.id) == ["w1", "u1", "u2"])
        #expect(!vm.visibleBestOfPlaylists.isEmpty)
    }

    @Test("Hiding Wrapped leaves the moods alone")
    func hideWrapped() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: [.wrapped], classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visiblePlaylists.map(\.id) == ["m1", "m2", "u1", "u2"])
    }

    @Test("Hiding the best-of playlists touches nothing on the server")
    func hideBestOf() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: [.artistBestOf], classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visibleBestOfPlaylists.isEmpty)
        #expect(vm.visiblePlaylists.map(\.id) == libraryFixture().map(\.id))
        // Hidden from the list, still loaded — revealing them again needs no refetch.
        #expect(!vm.bestOfPlaylists.isEmpty)
    }

    @Test("Hiding the user's own playlists leaves only what Cassette generated")
    func hideUserCreated() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: [.userCreated], classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visiblePlaylists.map(\.id) == ["m1", "m2", "w1"])
    }

    @Test("Kinds combine")
    func kindsCombine() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: [.moods, .wrapped, .artistBestOf],
                       classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visiblePlaylists.map(\.id) == ["u1", "u2"])
        #expect(vm.visibleBestOfPlaylists.isEmpty)
    }

    @Test("A renamed mood playlist is still hidden, through its cached id")
    func renamedMoodStillFiltered() async throws {
        let vm = try await loadedViewModel(playlists: [playlist("m9", "Late nights"), playlist("u1", "Road trip")])
        vm.applyFilter(hiddenKinds: [.moods], classifier: PlaylistClassifier(moodPlaylistIds: ["m9"]))
        #expect(vm.visiblePlaylists.map(\.id) == ["u1"])
    }

    // MARK: - Everything hidden

    @Test("Hiding every kind reports a filtered empty, not an empty library")
    func everythingHidden() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: Set(PlaylistKind.allCases),
                       classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visiblePlaylists.isEmpty)
        #expect(vm.visibleBestOfPlaylists.isEmpty)
        #expect(vm.isEmptyBecauseFiltered)
    }

    @Test("Clearing the filter restores the list with no refetch")
    func clearingRestores() async throws {
        let vm = try await loadedViewModel()
        vm.applyFilter(hiddenKinds: Set(PlaylistKind.allCases),
                       classifier: PlaylistClassifier(moodPlaylistIds: []))
        vm.applyFilter(hiddenKinds: [], classifier: PlaylistClassifier(moodPlaylistIds: []))
        #expect(vm.visiblePlaylists.map(\.id) == libraryFixture().map(\.id))
        #expect(!vm.isEmptyBecauseFiltered)
    }
}
