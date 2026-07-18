// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Observation
import OSLog
import SwiftSonic

@Observable
@MainActor
final class SongsListViewModel {
    /// Raw songs in server order; the view sorts client-side (needs `created`/`year`) then maps to
    /// `DisplayableSong`.
    var songs: [Song] = []
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
            songs = try await libraryService.allSongs()
        } catch {
            Logger.library.error("SongsListViewModel.load() failed: \(error, privacy: .public)")
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
