// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

/// Turning endless play off drops the tracks it appended. The only invariant that matters
/// to the listener is that the music does not stop — whatever is playing is never removed.
@Suite("Auto-extend — queue truncation on disable")
struct AutoExtendTruncationTests {

    private func target(boundary: Int?, currentIndex: Int, queueCount: Int) -> Int? {
        PlayerService.truncationTarget(boundary: boundary, currentIndex: currentIndex, queueCount: queueCount)
    }

    @Test("no boundary means endless play never appended anything")
    func noBoundaryIsANoOp() {
        #expect(target(boundary: nil, currentIndex: 3, queueCount: 12) == nil)
    }

    @Test("still inside the original queue drops the whole appended tail")
    func insideOriginalZoneDropsEverythingAppended() {
        // 10 user tracks + 50 appended, listening to track 3.
        #expect(target(boundary: 10, currentIndex: 3, queueCount: 60) == 10)
    }

    @Test("on the last original track still drops the tail")
    func lastOriginalTrackDropsTail() {
        #expect(target(boundary: 10, currentIndex: 9, queueCount: 60) == 10)
    }

    @Test("already inside the appended tail keeps the playing track and drops the rest")
    func insideExtendedZoneKeepsCurrentTrack() {
        // This is the case the old implementation bailed out of, leaving all 50 appended
        // tracks in the queue — the user turned endless play off and nothing happened.
        #expect(target(boundary: 10, currentIndex: 23, queueCount: 60) == 24)
    }

    @Test("first appended track survives as the new last entry")
    func firstAppendedTrackSurvives() {
        #expect(target(boundary: 10, currentIndex: 10, queueCount: 60) == 11)
    }

    @Test("playing the very last track leaves the queue alone")
    func lastTrackIsAlreadyTheEnd() {
        #expect(target(boundary: 10, currentIndex: 59, queueCount: 60) == nil)
    }

    @Test("a boundary at the queue end means nothing was appended after it")
    func boundaryAtEndIsANoOp() {
        #expect(target(boundary: 60, currentIndex: 3, queueCount: 60) == nil)
    }

    @Test("truncation never removes the track being played")
    func currentTrackAlwaysSurvives() {
        for currentIndex in 0..<60 {
            guard let target = target(boundary: 10, currentIndex: currentIndex, queueCount: 60) else { continue }
            #expect(target > currentIndex, "index \(currentIndex) would be cut out of a \(target)-track queue")
        }
    }
}
