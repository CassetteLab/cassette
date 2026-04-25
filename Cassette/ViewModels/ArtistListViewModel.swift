// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class ArtistListViewModel {
    var indexes: [ArtistIndex] = []
    var isLoading = false
    var error: Error?

    // Search state (merged from SearchViewModel)
    var searchResults: SearchResult3?
    var isSearching = false
    var searchError: Error?

    private let libraryService: any LibraryServiceProtocol

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            indexes = try await libraryService.artists()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = nil
            return
        }
        isSearching = true
        searchError = nil
        do {
            // 300 ms debounce: cancelled automatically if query changes before sleep ends
            try await Task.sleep(for: .milliseconds(300))
            searchResults = try await libraryService.search(trimmed)
        } catch is CancellationError {
            // Superseded by a newer query — do nothing
        } catch {
            searchError = error
        }
        isSearching = false
    }
}
