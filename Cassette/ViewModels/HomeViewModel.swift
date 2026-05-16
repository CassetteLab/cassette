// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Observation
import SwiftSonic

@Observable
@MainActor
final class HomeViewModel {
    private(set) var recentAlbums: [AlbumID3] = []
    private(set) var recentlyPlayed: [AlbumID3] = []
    private(set) var mostPlayed: [AlbumID3] = []
    var isLoading = false
    var error: UserFacingError?

    private let libraryService: any LibraryServiceProtocol

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let added = libraryService.recentlyAddedAlbums(size: 60)
            async let played = libraryService.recentlyPlayedAlbums(size: 20)
            async let most = libraryService.mostPlayedAlbums(size: 20)
            let (a, p, m) = try await (added, played, most)
            recentAlbums = a
            recentlyPlayed = p
            mostPlayed = m
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
