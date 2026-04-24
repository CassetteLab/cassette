// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class PlaylistDetailViewModel {
    var playlist: PlaylistWithSongs?
    var isLoading = false
    var error: Error?

    private let playlistId: String
    private let libraryService: any LibraryServiceProtocol

    init(playlistId: String, libraryService: any LibraryServiceProtocol) {
        self.playlistId = playlistId
        self.libraryService = libraryService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            playlist = try await libraryService.playlist(id: playlistId)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
