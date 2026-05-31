// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AVFoundation
import AudioStreaming
import OSLog

actor ReplayGainService {
    private let eqNode = AVAudioUnitEQ()
    private var isAttached = false

    func attach(to player: AudioPlayer) {
        guard !isAttached else { return }
        player.attach(node: eqNode)
        isAttached = true
    }

    /// Applies gain for the given track using a pre-captured settings snapshot.
    func apply(track: DisplayableSong, config: ReplayGainConfig) {
        eqNode.globalGain = Self.computeGain(
            enabled: config.enabled,
            mode: config.mode,
            preAmp: config.preAmp,
            preventClipping: config.preventClipping,
            trackGain: track.replayGainTrackGain,
            trackPeak: track.replayGainTrackPeak,
            albumGain: track.replayGainAlbumGain,
            albumPeak: track.replayGainAlbumPeak,
            baseGain: track.replayGainBaseGain,
            fallbackGain: track.replayGainFallbackGain
        )
    }

    /// Re-applies gain to the current track (nil track resets to 0 dB).
    func apply(currentTrack: DisplayableSong?, config: ReplayGainConfig) {
        guard let track = currentTrack else {
            eqNode.globalGain = 0
            return
        }
        apply(track: track, config: config)
    }

    /// Resets the EQ gain to 0 dB (no effect). Called when playback stops.
    func resetGain() {
        eqNode.globalGain = 0
    }

    // MARK: - Gain computation (pure, static, testable)

    /// Computes the EQ gain in dB from raw settings values and song RG fields.
    /// Returns 0.0 when disabled or when no gain data is available (play untouched).
    nonisolated static func computeGain(
        enabled: Bool,
        mode: ReplayGainMode,
        preAmp: Double,
        preventClipping: Bool,
        trackGain: Double?,
        trackPeak: Double?,
        albumGain: Double?,
        albumPeak: Double?,
        baseGain: Double?,
        fallbackGain: Double?
    ) -> Float {
        guard enabled else { return 0.0 }

        // Select gain and peak based on mode.
        let selectedGain: Double?
        let selectedPeak: Double?
        switch mode {
        case .track:
            selectedGain = trackGain
            selectedPeak = trackPeak
        case .album:
            selectedGain = albumGain
            selectedPeak = albumPeak
        }

        // Fall back to fallbackGain when the selected mode's gain is absent.
        // No reliable peak is available for the fallback tag, so peak is left nil.
        let gainDB: Double
        let peakLinear: Double?
        if let g = selectedGain {
            gainDB = g
            peakLinear = selectedPeak
        } else if let fg = fallbackGain {
            gainDB = fg
            peakLinear = nil
        } else {
            // No gain data at all — play untouched. Pre-amp is NOT applied.
            return 0.0
        }

        // baseGain (OpenSubsonic): always added to the selected gain when present.
        // preAmp: user-adjustable offset applied only when real gain data exists.
        let totalDB = gainDB + (baseGain ?? 0.0) + preAmp

        // Convert to linear amplitude for peak check.
        let gainLinear = pow(10.0, totalDB / 20.0)

        // Peak-limiting: prevent output from exceeding full scale.
        let finalLinear: Double
        if preventClipping, let peak = peakLinear, peak > 0 {
            finalLinear = min(gainLinear, 1.0 / peak)
        } else {
            finalLinear = gainLinear
        }

        let finalDB = 20.0 * log10(max(finalLinear, 0.0001))
        // AVAudioUnitEQ.globalGain valid range: −96…+24 dB
        return Float(finalDB.clamped(to: -96.0...24.0))
    }
}

// MARK: - Comparable clamping helper

fileprivate extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
