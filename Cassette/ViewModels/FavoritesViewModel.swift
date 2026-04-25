// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class FavoritesViewModel {
    var songs: [Song] = []
    var albums: [AlbumID3] = []
    var artists: [ArtistID3] = []
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
            let starred = try await libraryService.getStarred2()
            songs = starred.song ?? []
            albums = starred.album ?? []
            artists = starred.artist ?? []
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
