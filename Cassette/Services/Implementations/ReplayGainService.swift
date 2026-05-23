// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AVFoundation
import AudioStreaming

actor ReplayGainService {
    private let eqNode = AVAudioUnitEQ()
    private var isAttached = false

    func attach(to player: AudioPlayer) {
        guard !isAttached else { return }
        player.attach(node: eqNode)
        isAttached = true
    }

    func apply(track: DisplayableSong, enabled: Bool) {
        eqNode.globalGain = enabled ? computeGain(for: track) : 0
    }

    func setEnabled(_ enabled: Bool, currentTrack: DisplayableSong?) {
        guard let track = currentTrack else {
            eqNode.globalGain = 0
            return
        }
        apply(track: track, enabled: enabled)
    }

    // MARK: - Gain computation

    private func computeGain(for track: DisplayableSong) -> Float {
        let gainDB: Double
        let peakLinear: Double

        if let tg = track.replayGainTrackGain {
            gainDB = tg
            peakLinear = track.replayGainTrackPeak ?? 1.0
        } else if let ag = track.replayGainAlbumGain {
            gainDB = ag
            peakLinear = track.replayGainAlbumPeak ?? 1.0
        } else {
            return 0.0
        }

        // Peak limiting: clamp gain so gainLinear × peak ≤ 1.0
        let gainLinear = pow(10.0, gainDB / 20.0)
        let safePeak = max(peakLinear, 0.001)
        let clamped = min(gainLinear, 1.0 / safePeak)
        let clampedDB = 20.0 * log10(max(clamped, 0.0001))

        // AVAudioUnitEQ.globalGain range: -96…+24 dB
        return Float(clampedDB.clamped(to: -96.0...24.0))
    }
}

// MARK: - Comparable clamping helper

fileprivate extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
