// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

@Suite("PlaybackContinuationPlan")
struct PlaybackContinuationPlanTests {

    private func song(_ id: String) -> Song { Song(id: id, title: "Title \(id)", duration: 180) }

    private func plan(
        _ ids: [String],
        current: String? = nil,
        position: TimeInterval? = nil,
        localIds: [String] = [],
        localCurrent: String? = nil
    ) -> PlaybackContinuationPlan.Plan? {
        PlaybackContinuationPlan.make(
            entries: ids.map(song),
            current: current,
            position: position,
            localQueueIds: localIds,
            localCurrentId: localCurrent
        )
    }

    @Test("maps the remote queue in order and starts on the remote current song")
    func mapsQueue() throws {
        let result = try #require(plan(["a", "b", "c"], current: "b", position: 42))
        #expect(result.songIds == ["a", "b", "c"])
        #expect(result.currentIndex == 1)
        #expect(result.position == 42)
    }

    @Test("an unknown current song falls back to the start of the queue")
    func unknownCurrentFallsBackToZero() throws {
        let result = try #require(plan(["a", "b"], current: "gone"))
        #expect(result.currentIndex == 0)
    }

    @Test("a missing current song falls back to the start of the queue")
    func missingCurrentFallsBackToZero() throws {
        let result = try #require(plan(["a", "b"], current: nil))
        #expect(result.currentIndex == 0)
    }

    @Test("an empty remote queue brings nothing to adopt")
    func emptyQueueIsRejected() {
        #expect(plan([]) == nil)
    }

    @Test("the queue this device already has is ignored — that is our own upload")
    func ownUploadIsIgnored() {
        #expect(plan(["a", "b"], current: "a", localIds: ["a", "b"], localCurrent: "a") == nil)
    }

    @Test("the same songs at a different position are adopted")
    func sameSongsDifferentCurrentIsAdopted() throws {
        let result = try #require(plan(["a", "b"], current: "b", localIds: ["a", "b"], localCurrent: "a"))
        #expect(result.currentIndex == 1)
    }

    @Test("a different queue is adopted even when the current song matches")
    func differentQueueIsAdopted() throws {
        let result = try #require(plan(["a", "b", "c"], current: "a", localIds: ["a", "b"], localCurrent: "a"))
        #expect(result.songIds == ["a", "b", "c"])
    }

    @Test("a missing position restores from the start of the song")
    func missingPositionIsZero() throws {
        let result = try #require(plan(["a"], current: "a", position: nil))
        #expect(result.position == 0)
    }

    @Test("a negative position is clamped rather than trusted")
    func negativePositionIsClamped() throws {
        let result = try #require(plan(["a"], current: "a", position: -12))
        #expect(result.position == 0)
    }

    @Test("the preference is off until the user turns it on")
    func preferenceIsOptIn() throws {
        let suiteName = "cassette.tests.continuation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(PlaybackContinuationPreference.isEnabled(defaults: defaults) == false)
        defaults.set(true, forKey: PlaybackContinuationPreference.userDefaultsKey)
        #expect(PlaybackContinuationPreference.isEnabled(defaults: defaults) == true)
    }
}
