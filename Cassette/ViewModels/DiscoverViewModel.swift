// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

@Observable
@MainActor
final class DiscoverViewModel {
    private let libraryService: any LibraryServiceProtocol

    // MARK: - State

    private(set) var recentlyPlayed: [AlbumID3] = []
    private(set) var mostPlayed: [AlbumID3] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    // MARK: - Derived state

    /// True when the initial fetch is in progress and we have nothing to show yet.
    var isInitialLoading: Bool {
        isLoading && recentlyPlayed.isEmpty && mostPlayed.isEmpty
    }

    /// True when load failed and we have nothing to show.
    var isErrorState: Bool {
        loadError != nil && recentlyPlayed.isEmpty && mostPlayed.isEmpty
    }

    // MARK: - Loading

    func load(forceRefresh: Bool = false) async {
        if !forceRefresh, !recentlyPlayed.isEmpty, !mostPlayed.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let recent = libraryService.recentlyPlayedAlbums(size: 35)
            async let frequent = libraryService.mostPlayedAlbums(size: 35)
            let (recentResult, frequentResult) = try await (recent, frequent)
            self.recentlyPlayed = recentResult
            self.mostPlayed = frequentResult
            self.loadError = nil
        } catch {
            self.loadError = error
            Logger.discover.error("Failed to load Discover sections: \(error, privacy: .public)")
        }
    }
}
