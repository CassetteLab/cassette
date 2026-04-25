// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Observation
import SwiftSonic

@Observable
@MainActor
final class HomeViewModel {
    var recentAlbums: [AlbumID3] = []
    var isLoading = false
    var error: Error?

    private let libraryService: any LibraryServiceProtocol

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            recentAlbums = try await libraryService.recentlyAddedAlbums(size: 24)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
