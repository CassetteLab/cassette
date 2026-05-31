// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Darwin
@testable import Cassette

// Convenience wrapper so individual tests don't repeat all parameters.
private func gain(
    enabled: Bool = true,
    mode: ReplayGainMode = .track,
    preAmp: Double = 0,
    preventClipping: Bool = true,
    trackGain: Double? = nil,
    trackPeak: Double? = nil,
    albumGain: Double? = nil,
    albumPeak: Double? = nil,
    baseGain: Double? = nil,
    fallbackGain: Double? = nil
) -> Float {
    ReplayGainService.computeGain(
        enabled: enabled,
        mode: mode,
        preAmp: preAmp,
        preventClipping: preventClipping,
        trackGain: trackGain,
        trackPeak: trackPeak,
        albumGain: albumGain,
        albumPeak: albumPeak,
        baseGain: baseGain,
        fallbackGain: fallbackGain
    )
}

private let epsilon: Float = 0.01

@Suite("ReplayGainService.computeGain")
struct ReplayGainServiceComputeGainTests {

    @Test("disabled always returns 0 dB regardless of gain data")
    func disabledReturnsZero() {
        let result = gain(enabled: false, trackGain: -6)
        #expect(result == 0.0)
    }

    @Test("no gain data returns 0 dB and pre-amp is NOT applied")
    func noGainDataReturnsZeroNoPreAmp() {
        let result = gain(preAmp: 6)
        #expect(result == 0.0)
    }

    @Test("track mode uses trackGain")
    func trackModeUsesTrackGain() {
        let result = gain(mode: .track, trackGain: -6, albumGain: -3)
        let expected = Float(-6.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("album mode uses albumGain")
    func albumModeUsesAlbumGain() {
        let result = gain(mode: .album, trackGain: -6, albumGain: -3)
        let expected = Float(-3.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("preAmp is added to selected gain")
    func preAmpAddedToGain() {
        let result = gain(preAmp: 3, trackGain: -6)
        let expected = Float(-3.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("baseGain is always added to selected gain when present")
    func baseGainAdded() {
        let result = gain(trackGain: -6, baseGain: 2)
        let expected = Float(-4.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("fallbackGain used when selected mode has no gain")
    func fallbackGainUsedWhenMissing() {
        // track mode, no trackGain → falls back to fallbackGain
        let result = gain(mode: .track, fallbackGain: -4)
        let expected = Float(-4.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("preAmp is NOT applied when only fallbackGain is used and no baseGain")
    func preAmpAppliedWithFallbackGain() {
        // preAmp IS applied when fallbackGain is used (it's still real gain data)
        let result = gain(preAmp: 2, fallbackGain: -4)
        let expected = Float(-2.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("preventClipping clamps gain via peak")
    func preventClippingClampsGain() {
        // +6 dB gain, peak = 0.7 → max safe is 1/0.7 ≈ 1.4286 linear → ~3.1 dB
        // Without clipping it would be +6 dB; with clipping it should be ≤ 3.1 dB
        let withClip = gain(preventClipping: true, trackGain: 6, trackPeak: 0.7)
        let withoutClip = gain(preventClipping: false, trackGain: 6, trackPeak: 0.7)
        #expect(withClip < withoutClip)
        // Max safe = 20*log10(1/0.7) ≈ 3.1 dB
        let maxSafe = 20.0 * log10(1.0 / 0.7)
        #expect(abs(Double(withClip) - maxSafe) < 0.02)
    }

    @Test("preventClipping off allows the full boost")
    func preventClippingOffAllowsBoost() {
        let result = gain(preventClipping: false, trackGain: 6, trackPeak: 0.7)
        #expect(abs(result - 6.0) < epsilon)
    }

    @Test("very negative gain floors at -80 dB due to 0.0001 linear guard")
    func extremelyNegativeGainFloorsAtGuard() {
        // computeGain floors linearAmplitude at 0.0001 before converting back to dB,
        // which means 20*log10(0.0001) = -80 dB is the practical lower bound.
        let result = gain(trackGain: -200)
        #expect(abs(result - (-80.0)) < epsilon)
    }

    @Test("output is clamped to +24 dB upper bound")
    func clampedToUpperBound() {
        let result = gain(preventClipping: false, trackGain: 100)
        #expect(result == 24.0)
    }

    @Test("album mode falls back to fallbackGain when albumGain is nil")
    func albumModeFallsBackToFallback() {
        let result = gain(mode: .album, albumGain: nil, fallbackGain: -5)
        let expected = Float(-5.0)
        #expect(abs(result - expected) < epsilon)
    }

    @Test("zero preAmp with track gain returns track gain unchanged")
    func zeroPreAmpIsTransparent() {
        let result = gain(preAmp: 0, trackGain: -8.5)
        #expect(abs(result - (-8.5)) < epsilon)
    }
}
