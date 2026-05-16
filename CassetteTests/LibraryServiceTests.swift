// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - normalizeArtistName

@Suite("LibraryService — normalizeArtistName")
struct LibraryServiceNormalizationTests {

    @Test("strips leading and trailing whitespace")
    func stripsWhitespace() {
        #expect(LibraryService.normalizeArtistName("  Beatles  ") == "beatles")
    }

    @Test("lowercases ASCII")
    func lowercases() {
        #expect(LibraryService.normalizeArtistName("JAY-Z") == "jay-z")
    }

    @Test("folds diacritics")
    func foldsDiacritics() {
        #expect(LibraryService.normalizeArtistName("Stromaë") == "stromae")
        #expect(LibraryService.normalizeArtistName("Sigur Rós") == "sigur ros")
    }

    @Test("combines lowercasing, diacritics folding and trimming")
    func combined() {
        #expect(LibraryService.normalizeArtistName(" Sigur Rós ") == "sigur ros")
        #expect(LibraryService.normalizeArtistName("  Björk  ") == "bjork")
    }

    @Test("already-normalized string is unchanged")
    func idempotent() {
        let normalized = "the beatles"
        #expect(LibraryService.normalizeArtistName(normalized) == normalized)
    }
}
