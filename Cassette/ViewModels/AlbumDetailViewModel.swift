// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class AlbumDetailViewModel {
    var album: AlbumID3?
    var isLoading = false
    var error: Error?

    private let albumId: String
    private let libraryService: any LibraryServiceProtocol

    init(albumId: String, libraryService: any LibraryServiceProtocol) {
        self.albumId = albumId
        self.libraryService = libraryService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            album = try await libraryService.album(id: albumId)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
