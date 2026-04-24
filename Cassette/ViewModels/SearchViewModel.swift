// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var results: SearchResult3?
    var isLoading = false
    var error: Error?

    private let libraryService: any LibraryServiceProtocol

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = nil
            return
        }
        isLoading = true
        error = nil
        do {
            // 300 ms debounce: cancels automatically if query changes before sleep ends
            try await Task.sleep(for: .milliseconds(300))
            results = try await libraryService.search(trimmed)
        } catch is CancellationError {
            // Superseded by a newer query — do nothing
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
