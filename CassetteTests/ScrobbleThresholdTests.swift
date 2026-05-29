// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("ScrobbleThresholdDetector")
struct ScrobbleThresholdTests {

    // MARK: - Fires at threshold

    @Test("fires exactly at 0.5 × duration for short tracks (< 480 s)")
    func firesAtExactHalfShortTrack() {
        var d = ScrobbleThresholdDetector()
        // threshold = min(240, 100 × 0.5) = 50
        let fired = d.check(duration: 100, accumulated: 50)
        #expect(fired)
    }

    @Test("fires exactly at 240 s for long tracks (> 480 s)")
    func firesAtCappedThresholdLongTrack() {
        var d = ScrobbleThresholdDetector()
        // threshold = min(240, 600 × 0.5) = 240
        let fired = d.check(duration: 600, accumulated: 240)
        #expect(fired)
    }

    @Test("fires when accumulated exceeds threshold")
    func firesAboveThreshold() {
        var d = ScrobbleThresholdDetector()
        // threshold = min(240, 300 × 0.5) = 150 — accumulated 200 exceeds it
        let fired = d.check(duration: 300, accumulated: 200)
        #expect(fired)
    }

    // MARK: - Does NOT fire

    @Test("does not fire when duration is below 30 s regardless of accumulated time")
    func doesNotFireForSubThirtySecondTrack() {
        var d = ScrobbleThresholdDetector()
        let fired = d.check(duration: 20, accumulated: 200)
        #expect(!fired)
    }

    @Test("does not fire when accumulated is below 0.5 × duration")
    func doesNotFireBelowAccumulatedThreshold() {
        var d = ScrobbleThresholdDetector()
        // threshold = 150, accumulated = 100 → below
        let fired = d.check(duration: 300, accumulated: 100)
        #expect(!fired)
    }

    @Test("does not fire when accumulated is below threshold at duration boundary (30 s)")
    func doesNotFireAtDurationBoundaryWithInsufficientAccumulated() {
        var d = ScrobbleThresholdDetector()
        // threshold = min(240, 15) = 15 — accumulated 10 is below
        let fired = d.check(duration: 30, accumulated: 10)
        #expect(!fired)
    }

    // MARK: - One-shot

    @Test("fired flag is false on fresh detector")
    func initiallyNotFired() {
        #expect(!ScrobbleThresholdDetector().fired)
    }

    @Test("fired flag becomes true after crossing threshold")
    func firedFlagSetAfterFiring() {
        var d = ScrobbleThresholdDetector()
        _ = d.check(duration: 300, accumulated: 200)
        #expect(d.fired)
    }

    @Test("one-shot: returns true once then false on all subsequent calls")
    func oneShot() {
        var d = ScrobbleThresholdDetector()
        let first = d.check(duration: 300, accumulated: 200)
        let second = d.check(duration: 300, accumulated: 200)
        let third = d.check(duration: 300, accumulated: 300)
        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    // MARK: - Reset

    @Test("reset clears fired flag and allows a second fire")
    func resetAllowsSecondFire() {
        var d = ScrobbleThresholdDetector()
        _ = d.check(duration: 300, accumulated: 200)
        d.reset()
        #expect(!d.fired)
        let refired = d.check(duration: 300, accumulated: 200)
        #expect(refired)
    }

    @Test("reset on a fresh detector is a no-op")
    func resetOnFreshDetectorIsNoOp() {
        var d = ScrobbleThresholdDetector()
        d.reset()
        #expect(!d.fired)
        let fired = d.check(duration: 300, accumulated: 200)
        #expect(fired)
    }
}
