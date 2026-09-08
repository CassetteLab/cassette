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

@Suite("Playback report")
struct PlaybackReportTests {

    @Test("keeps OpenSubsonic playback state names stable")
    func stateNames() {
        #expect(PlaybackReportState.allCases.map(\.rawValue) == ["starting", "playing", "paused", "stopped"])
        #expect(PlaybackReportState.allCases.map { LibraryService.swiftSonicPlaybackReportState(for: $0).rawValue } == PlaybackReportState.allCases.map(\.rawValue))
    }

    @Test("converts finite playback positions to non-negative milliseconds")
    func positionMilliseconds() {
        #expect(PlayerService.playbackReportPositionMilliseconds(263.964) == 263_964)
        #expect(PlayerService.playbackReportPositionMilliseconds(-1) == 0)
        #expect(PlayerService.playbackReportPositionMilliseconds(.infinity) == 0)
        #expect(PlayerService.playbackReportPositionMilliseconds(.nan) == 0)
        #expect(PlayerService.playbackReportPositionMilliseconds(.greatestFiniteMagnitude) == Int.max)
    }
}
