// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class ArtistDetailViewModel {
    var artist: ArtistID3?
    var isLoading = false
    var isPlayLoading = false
    var error: UserFacingError?

    private let artistId: String
    private let libraryService: any LibraryServiceProtocol

    init(artistId: String, libraryService: any LibraryServiceProtocol) {
        self.artistId = artistId
        self.libraryService = libraryService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            artist = try await libraryService.artist(id: artistId)
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
