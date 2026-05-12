// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import AppIntents

nonisolated struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Lecture / Pause"

    func perform() async throws -> some IntentResult {
        await NowPlayingBridge.performTogglePlayPause?()
        return .result()
    }
}
#endif
