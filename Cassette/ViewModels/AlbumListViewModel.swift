// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Observation
import SwiftSonic

@Observable
@MainActor
final class AlbumListViewModel {
    var albums: [AlbumID3] = []
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
            albums = try await libraryService.allAlbums()
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
