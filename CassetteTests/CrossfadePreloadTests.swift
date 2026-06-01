// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
@testable import Cassette

// MARK: - crossfadeVolume (equal-power curve)

@Suite("PlayerService.crossfadeVolume")
struct CrossfadeVolumeTests {

    @Test func fadeOutStartsAtBase() {
        #expect(PlayerService.crossfadeVolume(base: 1.0, progress: 0, phase: .fadeOut) == 1.0)
    }

    @Test func fadeOutEndsAtZero() {
        #expect(PlayerService.crossfadeVolume(base: 1.0, progress: 1, phase: .fadeOut) < 0.001)
    }

    @Test func fadeInStartsAtZero() {
        #expect(PlayerService.crossfadeVolume(base: 1.0, progress: 0, phase: .fadeIn) < 0.001)
    }

    @Test func fadeInEndsAtBase() {
        #expect(PlayerService.crossfadeVolume(base: 1.0, progress: 1, phase: .fadeIn) > 0.999)
    }

    @Test func midpointSumGreaterThanLinear() {
        // Equal-power: cos²(45°) + sin²(45°) = 1, each ≈ 0.707 vs 0.5 linear
        let out = PlayerService.crossfadeVolume(base: 1.0, progress: 0.5, phase: .fadeOut)
        let inV = PlayerService.crossfadeVolume(base: 1.0, progress: 0.5, phase: .fadeIn)
        #expect(Double(out) > 0.7 && Double(inV) > 0.7)
    }

    @Test func progressClampedBelow() {
        let v = PlayerService.crossfadeVolume(base: 0.8, progress: -1.0, phase: .fadeOut)
        #expect(v == PlayerService.crossfadeVolume(base: 0.8, progress: 0, phase: .fadeOut))
    }

    @Test func progressClampedAbove() {
        let v = PlayerService.crossfadeVolume(base: 0.8, progress: 2.0, phase: .fadeIn)
        #expect(v == PlayerService.crossfadeVolume(base: 0.8, progress: 1, phase: .fadeIn))
    }
}

// MARK: - shouldSchedulePrefetch

@Suite("PlayerService.shouldSchedulePrefetch")
struct ShouldSchedulePrefetchTests {

    @Test func dormantWhenDurationIsZero() {
        // Default crossfade duration = 0 → prefetch must never fire
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 0) == false)
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 5) == false)
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 100) == false)
    }

    @Test func firesWhenRemainingWithinThreshold() {
        // threshold = duration + 15; remaining=20 with duration=8 → 20 <= 23 → true
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 8, remaining: 20) == true)
    }

    @Test func exactlyAtThreshold() {
        // remaining == crossfadeDuration + 15 → should fire (≤)
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 5, remaining: 20) == true)
    }

    @Test func doesNotFireBeyondThreshold() {
        // remaining=21 with duration=5 → 21 > 20 → false
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 5, remaining: 21) == false)
    }

    @Test func firesNearEndOfTrack() {
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 3, remaining: 2) == true)
    }
}

// MARK: - shouldStartFadeOut

@Suite("PlayerService.shouldStartFadeOut")
struct ShouldStartFadeOutTests {

    // 120 s: never hits the short-track guard (2 * 5 = 10)
    @Test func dormantWhenDurationIsZero() {
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 0, remaining: 0.5, hasNext: true, trackDuration: 120) == false)
    }

    @Test func dormantWhenNoNextTrack() {
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 3, hasNext: false, trackDuration: 120) == false)
    }

    @Test func dormantWhenRemainingIsZero() {
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 0, hasNext: true, trackDuration: 120) == false)
    }

    @Test func firesWhenWithinWindow() {
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 4, hasNext: true, trackDuration: 120) == true)
    }

    @Test func firesAtExactBoundary() {
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 5, hasNext: true, trackDuration: 120) == true)
    }

    @Test func doesNotFireBeyondWindow() {
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 5.1, hasNext: true, trackDuration: 120) == false)
    }

    @Test func shortTrackSkipsFade() {
        // trackDuration=8 <= 2*5=10 → skip regardless of remaining
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 3, hasNext: true, trackDuration: 8) == false)
    }

    @Test func exactlyDoubleSkipsFade() {
        // trackDuration == 2*duration is still "not long enough"
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 3, hasNext: true, trackDuration: 10) == false)
    }

    @Test func justOverDoubleAllowsFade() {
        // trackDuration=10.1 > 10 → allow
        #expect(PlayerService.shouldStartFadeOut(crossfadeDuration: 5, remaining: 3, hasNext: true, trackDuration: 10.1) == true)
    }
}

// MARK: - shouldProceedWithPrefetch

@Suite("PlayerService.shouldProceedWithPrefetch")
struct ShouldProceedWithPrefetchTests {

    @Test func proceedsOnWifi() {
        #expect(PlayerService.shouldProceedWithPrefetch(isExpensive: false, allowCellular: false) == true)
    }

    @Test func proceedsOnCellularWhenAllowed() {
        #expect(PlayerService.shouldProceedWithPrefetch(isExpensive: true, allowCellular: true) == true)
    }

    @Test func blockedOnCellularWhenNotAllowed() {
        #expect(PlayerService.shouldProceedWithPrefetch(isExpensive: true, allowCellular: false) == false)
    }

    @Test func proceedsWhenNotExpensiveRegardlessOfAllowCellular() {
        // isExpensive=false means we're on Wi-Fi; allowCellular flag is irrelevant
        #expect(PlayerService.shouldProceedWithPrefetch(isExpensive: false, allowCellular: true) == true)
        #expect(PlayerService.shouldProceedWithPrefetch(isExpensive: false, allowCellular: false) == true)
    }
}

// MARK: - isGaplessPair

@Suite("PlayerService.isGaplessPair")
struct IsGaplessPairTests {

    @Test func sameAlbumConsecutiveIsGapless() {
        #expect(PlayerService.isGaplessPair(
            currentAlbumId: "A", currentTrackNumber: 3,
            nextAlbumId: "A", nextTrackNumber: 4
        ) == true)
    }

    @Test func differentAlbumIsNotGapless() {
        #expect(PlayerService.isGaplessPair(
            currentAlbumId: "A", currentTrackNumber: 3,
            nextAlbumId: "B", nextTrackNumber: 4
        ) == false)
    }

    @Test func nonConsecutiveIsNotGapless() {
        #expect(PlayerService.isGaplessPair(
            currentAlbumId: "A", currentTrackNumber: 3,
            nextAlbumId: "A", nextTrackNumber: 5
        ) == false)
    }

    @Test func nilAlbumIdIsNotGapless() {
        #expect(PlayerService.isGaplessPair(
            currentAlbumId: nil, currentTrackNumber: 3,
            nextAlbumId: "A", nextTrackNumber: 4
        ) == false)
        #expect(PlayerService.isGaplessPair(
            currentAlbumId: "A", currentTrackNumber: 3,
            nextAlbumId: nil, nextTrackNumber: 4
        ) == false)
    }

    @Test func nilTrackNumberIsNotGapless() {
        #expect(PlayerService.isGaplessPair(
            currentAlbumId: "A", currentTrackNumber: nil,
            nextAlbumId: "A", nextTrackNumber: 4
        ) == false)
    }
}
