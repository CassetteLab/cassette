// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

private func playlist(id: String, name: String, songCount: Int = 10) -> Playlist {
    Playlist(id: id, name: name, songCount: songCount, duration: songCount * 200)
}

// MARK: - Classification

@Suite("Playlist classification")
struct PlaylistClassifierTests {

    @Test("A cached mood id is a mood playlist whatever it is called")
    func cachedMoodIdWins() {
        let classifier = PlaylistClassifier(moodPlaylistIds: ["pl-7"])
        // The user renamed it: only the cached id still ties it to the mood.
        #expect(classifier.kind(of: playlist(id: "pl-7", name: "Late nights")) == .moods)
    }

    @Test("The mood prefix classifies without any cached id")
    func moodPrefixFallback() {
        // Empty cache is what a fresh reinstall looks like.
        let classifier = PlaylistClassifier(moodPlaylistIds: [])
        for mood in Mood.allCases {
            #expect(classifier.kind(of: playlist(id: "x-\(mood.rawValue)", name: mood.playlistName)) == .moods)
        }
    }

    @Test("Cassette Wrapped is its own kind when a year follows the prefix")
    func wrappedNeedsAYear() {
        let classifier = PlaylistClassifier(moodPlaylistIds: [])
        #expect(classifier.kind(of: playlist(id: "w1", name: "Cassette Wrapped 2025")) == .wrapped)
        // No parseable year: this is something the user made, not a generated playlist.
        #expect(classifier.kind(of: playlist(id: "w2", name: "Cassette Wrapped Favourites")) == .userCreated)
    }

    @Test("Anything else is the user's own playlist")
    func everythingElseIsUserCreated() {
        let classifier = PlaylistClassifier(moodPlaylistIds: ["pl-7"])
        for name in ["Road trip", "Cassette", "cassette · night", "The best of Radiohead", "Le meilleur de Daft Punk"] {
            #expect(classifier.kind(of: playlist(id: UUID().uuidString, name: name)) == .userCreated,
                    "\(name) should stay the user's")
        }
    }

    @Test("Mood ids are read from the per-server cache")
    func readsMoodIdsFromPreferences() throws {
        let suiteName = "PlaylistKindTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MoodPreferences(userDefaults: defaults)
        preferences.setPlaylistId("srv-night", mood: .night, serverId: "server-a")
        // Another server's cache must not leak into this one.
        preferences.setPlaylistId("srv-other", mood: .chill, serverId: "server-b")

        let classifier = PlaylistClassifier(serverId: "server-a", moodPreferences: preferences)
        #expect(classifier.kind(of: playlist(id: "srv-night", name: "Renamed")) == .moods)
        #expect(classifier.kind(of: playlist(id: "srv-other", name: "Renamed")) == .userCreated)
    }
}

// MARK: - Persisted filter

@Suite("Playlist filter persistence")
struct PlaylistKindFilterTests {

    @Test("No stored value hides nothing — the behaviour that shipped before the filter")
    func nilHidesNothing() {
        #expect(PlaylistKind.decodeHidden(nil).isEmpty)
        #expect(PlaylistKind.decodeHidden("").isEmpty)
    }

    @Test("An empty hidden set stores as nil, not as an empty string")
    func emptyEncodesToNil() {
        #expect(PlaylistKind.encodeHidden([]) == nil)
    }

    @Test("Every kind round-trips through storage")
    func roundTrip() {
        for subset in [Set<PlaylistKind>([.moods]), [.artistBestOf, .wrapped], Set(PlaylistKind.allCases)] {
            #expect(PlaylistKind.decodeHidden(PlaylistKind.encodeHidden(subset)) == subset)
        }
    }

    @Test("Encoding is stable regardless of set ordering, so saves don't churn")
    func encodingIsStable() {
        let a = PlaylistKind.encodeHidden([.userCreated, .moods, .wrapped])
        let b = PlaylistKind.encodeHidden([.wrapped, .moods, .userCreated])
        #expect(a == b)
        #expect(a == "moods,wrapped,userCreated")
    }

    @Test("An unknown stored kind is ignored rather than breaking the filter")
    func unknownRawValuesAreDropped() {
        #expect(PlaylistKind.decodeHidden("moods,doesNotExist,wrapped") == [.moods, .wrapped])
    }

    @Test("The last checked kind cannot be cleared")
    func lastVisibleIsLocked() {
        // Three of four hidden: the survivor is locked, the hidden ones stay free to re-check.
        let hidden: Set<PlaylistKind> = [.moods, .wrapped, .artistBestOf]
        #expect(PlaylistKind.isLastVisible(.userCreated, hidden: hidden))
        for kind in hidden {
            #expect(!PlaylistKind.isLastVisible(kind, hidden: hidden), "\(kind) is hidden, not the survivor")
        }
    }

    @Test("Nothing is locked while more than one kind is shown")
    func nothingLockedOtherwise() {
        for hidden in [Set<PlaylistKind>(), [.moods], [.moods, .wrapped]] {
            for kind in PlaylistKind.allCases {
                #expect(!PlaylistKind.isLastVisible(kind, hidden: hidden))
            }
        }
    }

    @Test("Display order covers every kind exactly once")
    func displayOrderIsComplete() {
        #expect(Set(PlaylistKind.displayOrder) == Set(PlaylistKind.allCases))
        #expect(PlaylistKind.displayOrder.count == PlaylistKind.allCases.count)
    }
}
