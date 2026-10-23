// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import AudioStreaming
@testable import Cassette

@Suite("Stream stall — detection and recovery decision")
struct StreamStallTests {

    /// Production timing: 15 s mid-track, 30 s before the first sample, reopened once at 12 s.
    private let timing = PlayerService.StreamStallTiming()

    /// Feeds one progress value per one-second tick and returns every step.
    private func steps(_ progress: [TimeInterval], isPlaying: Bool = true, isOnline: Bool = true) -> [PlayerService.StreamStallStep] {
        var watch = PlayerService.StreamStallWatch()
        return progress.map { value in
            let result = PlayerService.streamStallTick(
                watch, progress: value, isPlaying: isPlaying, isOnline: isOnline, elapsed: .seconds(1), timing: timing
            )
            watch = result.watch
            return result.step
        }
    }

    private func fails(_ steps: [PlayerService.StreamStallStep]) -> Bool {
        steps.contains(.failUnreachable) || steps.contains(.failOffline)
    }

    @Test("a stream that never starts fails as unreachable after 30 seconds")
    func neverStartingStreamFails() {
        #expect(steps(Array(repeating: 0, count: 31)).last == .failUnreachable)
    }

    @Test("a stream that never starts does not fail before 30 seconds")
    func neverStartingStreamWaitsForTimeout() {
        #expect(!fails(steps(Array(repeating: 0, count: 30))))
    }

    @Test("a stream that never starts is opened again once, after twelve seconds")
    func neverStartingStreamIsReopened() {
        let result = steps(Array(repeating: 0, count: 30))
        let reopened = result.indices.filter { result[$0] == .restartSource }
        #expect(reopened == [12])
    }

    @Test("a slow start, like a non-faststart m4a, is neither reopened nor failed")
    func slowStartIsNotReopened() {
        let result = steps(Array(repeating: 0, count: 11) + [0.5, 1.5])
        #expect(!result.contains(.restartSource))
        #expect(!fails(result))
    }

    @Test("a stream stuck mid-track is not reopened, AudioStreaming retries it itself")
    func midTrackUnderrunIsNotReopened() {
        let result = steps((0..<30).map(TimeInterval.init) + Array(repeating: 29, count: 16))
        #expect(!result.contains(.restartSource))
        #expect(result.last == .failUnreachable)
    }

    @Test("offline, a stalled stream fails at once instead of after the timeout")
    func offlineFailsImmediately() {
        let result = steps([0, 0], isOnline: false)
        #expect(result == [.wait, .failOffline])
    }

    @Test("offline, a stream still playing from its buffer keeps playing")
    func offlineBufferKeepsPlaying() {
        #expect(!fails(steps((0..<20).map(TimeInterval.init), isOnline: false)))
    }

    @Test("offline, the stream fails as soon as the buffer runs out")
    func offlineBufferRunsOut() {
        let result = steps([1, 2, 3, 3], isOnline: false)
        #expect(result == [.wait, .wait, .wait, .failOffline])
    }

    @Test("a slow but moving stream never stalls")
    func slowStreamKeepsPlaying() {
        #expect(!fails(steps((0..<60).map { TimeInterval($0) * 0.2 })))
    }

    @Test("progress resets the stall clock")
    func progressResetsClock() {
        #expect(!fails(steps(Array(repeating: 0.0, count: 14) + [1] + Array(repeating: 1.0, count: 14))))
    }

    @Test("a backwards seek counts as movement")
    func backwardsSeekResetsClock() {
        #expect(!fails(steps(Array(repeating: 40.0, count: 14) + Array(repeating: 10.0, count: 14))))
    }

    @Test("paused time never counts towards a stall, online or offline")
    func pausedDoesNotStall() {
        #expect(steps(Array(repeating: 12, count: 100), isPlaying: false).allSatisfy { $0 == .wait })
        #expect(steps(Array(repeating: 0, count: 100), isPlaying: false, isOnline: false).allSatisfy { $0 == .wait })
    }

    @Test("a pause in the middle restarts the stall clock")
    func pauseRestartsClock() {
        var watch = PlayerService.StreamStallWatch()
        for _ in 0..<14 {
            watch = PlayerService.streamStallTick(watch, progress: 5, isPlaying: true, isOnline: true, elapsed: .seconds(1), timing: timing).watch
        }
        watch = PlayerService.streamStallTick(watch, progress: 5, isPlaying: false, isOnline: true, elapsed: .seconds(1), timing: timing).watch
        let result = PlayerService.streamStallTick(watch, progress: 5, isPlaying: true, isOnline: true, elapsed: .seconds(1), timing: timing)
        #expect(result.step == .wait)
    }

    @Test("the timing is the caller's, not a constant")
    func timingIsInjected() {
        let fast = PlayerService.StreamStallTiming(
            timeout: .milliseconds(20), startTimeout: .milliseconds(40), restartAfter: .milliseconds(30), interval: .milliseconds(10)
        )
        func tick(_ watch: PlayerService.StreamStallWatch) -> (watch: PlayerService.StreamStallWatch, step: PlayerService.StreamStallStep) {
            PlayerService.streamStallTick(watch, progress: 3, isPlaying: true, isOnline: true, elapsed: .milliseconds(10), timing: fast)
        }
        let second = tick(tick(.init()).watch)
        #expect(second.step == .wait)
        #expect(tick(second.watch).step == .failUnreachable)
    }

    // MARK: - Recovery

    private let stream = MediaSource.stream(URL(string: "https://music.example/rest/stream?id=1")!, customHeaders: [:])
    private let file = URL(fileURLWithPath: "/tmp/song.mp3")

    @Test("a downloaded copy continues the track")
    func downloadedCopyPlaysLocal() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: .downloaded(file)) == .playLocal)
    }

    @Test("a cached copy continues the track")
    func cachedCopyPlaysLocal() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: .cached(file)) == .playLocal)
    }

    @Test("without a local copy playback stops with an error")
    func noLocalCopyStops() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: stream) == .stop)
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: nil) == .stop)
    }

    @Test("a second failure report for the stopped stream does nothing")
    func secondReportIsIgnored() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: true, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
    }

    @Test("a network error reported in the error state still recovers the stream")
    func errorStateRecovers() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .error(.timeout), interrupted: false, progressMoved: false, localCopy: .cached(file)) == .playLocal)
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .error(.timeout), interrupted: false, progressMoved: false, localCopy: nil) == .stop)
    }

    @Test("a stream failure while paused or stopped does nothing: no audio, no error")
    func userPauseWins() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .paused, interrupted: false, progressMoved: false, localCopy: .cached(file)) == .ignore)
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .paused, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .idle, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
    }

    @Test("a pause or stop that ran while the failure was handled wins, even if the state snapshot said playing")
    func interruptionWins() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: true, progressMoved: false, localCopy: .cached(file)) == .ignore)
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: true, progressMoved: false, localCopy: nil) == .ignore)
    }

    @Test("a stream that moved again during the failure handling, after a seek, is watched again instead of replaced")
    func movedStreamIsWatchedAgain() {
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: true, localCopy: .cached(file)) == .watchAgain)
        #expect(PlayerService.streamFailureAction(source: stream, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: true, localCopy: nil) == .watchAgain)
    }

    @Test("local files and radio are not handled as stalled streams")
    func nonStreamSourcesAreIgnored() {
        #expect(PlayerService.streamFailureAction(source: .downloaded(file), alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
        #expect(PlayerService.streamFailureAction(source: .cached(file), alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
        let radio = MediaSource.liveStream(URL(string: "https://radio.example/live")!, customHeaders: [:], stationId: "r")
        #expect(PlayerService.streamFailureAction(source: radio, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
        #expect(PlayerService.streamFailureAction(source: nil, alreadyStopped: false, playbackState: .playing, interrupted: false, progressMoved: false, localCopy: nil) == .ignore)
    }

    @Test("the failures use the existing server and offline messages")
    func userFacingMessages() {
        #expect(UserFacingError.from(CassetteError.serverUnreachable) == .serverUnreachable)
        #expect(UserFacingError.from(CassetteError.offlineUnavailable(songId: "1")) == .contentUnavailableOffline)
    }

    // MARK: - Resume

    @Test("resume starts a stopped or failed track again instead of resuming a dead engine")
    func resumeRestartsDeadEngine() {
        #expect(PlayerService.resumeRestartsSource(engineState: .stopped, source: stream))
        #expect(PlayerService.resumeRestartsSource(engineState: .error, source: stream))
        #expect(PlayerService.resumeRestartsSource(engineState: .ready, source: stream))
        #expect(PlayerService.resumeRestartsSource(engineState: .stopped, source: .downloaded(file)))
    }

    @Test("resume of a paused engine resumes it")
    func resumeKeepsPausedEngine() {
        #expect(!PlayerService.resumeRestartsSource(engineState: .paused, source: stream))
        #expect(!PlayerService.resumeRestartsSource(engineState: .playing, source: stream))
        #expect(!PlayerService.resumeRestartsSource(engineState: .bufferring, source: stream))
    }

    @Test("resume never restarts without a source or for radio")
    func resumeIgnoresRadioAndEmpty() {
        let radio = MediaSource.liveStream(URL(string: "https://radio.example/live")!, customHeaders: [:], stationId: "r")
        #expect(!PlayerService.resumeRestartsSource(engineState: .stopped, source: radio))
        #expect(!PlayerService.resumeRestartsSource(engineState: .stopped, source: nil))
    }
}
