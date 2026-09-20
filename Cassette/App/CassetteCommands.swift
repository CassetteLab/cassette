// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct CassetteCommands: Commands {
    /// Passed in rather than read from the environment: a `Commands` body sits outside the
    /// view hierarchy, so it has no `appContainer`. Same shape as `CassetteSettingsScene`.
    let container: AppContainer?

    /// Seeking is meaningless without a track, and impossible on a live stream.
    private var seekUnavailable: Bool {
        guard let state = container?.playerState else { return true }
        return state.currentTrack == nil || state.isLiveStream
    }

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play / Pause") {
                NotificationCenter.default.post(name: .cassetteTogglePlayPause, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Next Track") {
                NotificationCenter.default.post(name: .cassetteSkipNext, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Previous Track") {
                NotificationCenter.default.post(name: .cassetteSkipPrevious, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Skip Back 10 Seconds") {
                NotificationCenter.default.post(name: .cassetteSeekBackward, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .option)
            .disabled(seekUnavailable)

            Button("Skip Forward 10 Seconds") {
                NotificationCenter.default.post(name: .cassetteSeekForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .option)
            .disabled(seekUnavailable)

            Divider()

            Button("Toggle Shuffle") {
                NotificationCenter.default.post(name: .cassetteToggleShuffle, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Toggle Repeat") {
                NotificationCenter.default.post(name: .cassetteToggleRepeat, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Show Queue") {
                NotificationCenter.default.post(name: .cassetteToggleQueue, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Search") {
                NotificationCenter.default.post(name: .cassetteFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
#endif
