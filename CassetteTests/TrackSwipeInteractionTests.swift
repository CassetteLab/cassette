// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@MainActor
@Suite("TrackSwipeInteraction")
struct TrackSwipeInteractionTests {

    private func destination(
        _ direction: TrackSwipeInteraction.Direction,
        at index: Int,
        of count: Int,
        repeatMode: RepeatMode = .off
    ) -> Int? {
        TrackSwipeInteraction.destinationIndex(
            direction,
            currentIndex: index,
            queueCount: count,
            repeatMode: repeatMode
        )
    }

    // MARK: - Where a swipe can go

    @Test("an empty queue has nowhere to swipe")
    func emptyQueue() {
        #expect(destination(.next, at: 0, of: 0) == nil)
        #expect(destination(.previous, at: 0, of: 0) == nil)
    }

    @Test("a single-track queue has nowhere to swipe")
    func singleTrackQueue() {
        #expect(destination(.next, at: 0, of: 1) == nil)
        #expect(destination(.previous, at: 0, of: 1) == nil)
    }

    @Test("mid-queue, a swipe moves one track in each direction")
    func midQueue() {
        #expect(destination(.next, at: 1, of: 3) == 2)
        #expect(destination(.previous, at: 1, of: 3) == 0)
    }

    @Test("without repeat, the ends of the queue are boundaries")
    func endsWithoutRepeat() {
        #expect(destination(.next, at: 2, of: 3) == nil)
        #expect(destination(.previous, at: 0, of: 3) == nil)
    }

    @Test("repeat-all wraps forward from the last track")
    func wrapsForward() {
        #expect(destination(.next, at: 2, of: 3, repeatMode: .all) == 0)
    }

    @Test("repeat-all wraps backward from the first track — the gesture is symmetric")
    func wrapsBackward() {
        #expect(destination(.previous, at: 0, of: 3, repeatMode: .all) == 2)
    }

    @Test("repeat-one does not wrap: it is not a queue-level mode")
    func repeatOneDoesNotWrap() {
        #expect(destination(.next, at: 2, of: 3, repeatMode: .one) == nil)
        #expect(destination(.previous, at: 0, of: 3, repeatMode: .one) == nil)
    }

    @Test("an index outside the queue has nowhere to swipe")
    func indexOutOfRange() {
        #expect(destination(.next, at: 7, of: 3) == nil)
        #expect(destination(.previous, at: -1, of: 3) == nil)
    }

    // MARK: - Dead zone

    @Test("a drag inside the dead zone does not move the page")
    func insideDeadZone() {
        #expect(TrackSwipeInteraction.activeTranslation(12, deadZone: 20) == 0)
        #expect(TrackSwipeInteraction.activeTranslation(-12, deadZone: 20) == 0)
    }

    @Test("a drag exactly at the dead zone edge does not move the page")
    func atDeadZoneEdge() {
        #expect(TrackSwipeInteraction.activeTranslation(20, deadZone: 20) == 0)
        #expect(TrackSwipeInteraction.activeTranslation(-20, deadZone: 20) == 0)
    }

    @Test("past the dead zone, the page follows the finger minus the dead zone")
    func pastDeadZone() {
        #expect(TrackSwipeInteraction.activeTranslation(50, deadZone: 20) == 30)
        #expect(TrackSwipeInteraction.activeTranslation(-50, deadZone: 20) == -30)
    }
}
