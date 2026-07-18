// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class PlaylistListViewModel {
    var playlists: [Playlist] = []
    var isLoading = false
    var error: UserFacingError?

    private let libraryService: any LibraryServiceProtocol

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    /// Virtual "best of" playlists derived from the user's stars — never server playlists, so they are
    /// kept in their own section rather than mixed into `playlists`.
    var bestOfPlaylists: [ArtistBestOf] = []

    /// Loads the derived best-of playlists. Independent of `load()` and deliberately non-throwing: a server
    /// that fails or doesn't answer getStarred2 should cost the user the "Made For You" section, not the
    /// playlist list.
    func loadBestOf() async {
        guard let starred = try? await libraryService.getStarred2() else {
            bestOfPlaylists = []
            return
        }
        bestOfPlaylists = ArtistBestOf.all(in: starred.song ?? [])
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            playlists = try await libraryService.playlists()
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
