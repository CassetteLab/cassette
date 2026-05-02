// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct CassetteCommands: Commands {
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

            Divider()

            Button("Toggle Shuffle") {
                NotificationCenter.default.post(name: .cassetteToggleShuffle, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Toggle Repeat") {
                NotificationCenter.default.post(name: .cassetteToggleRepeat, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Sidebar") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Search") {
                NotificationCenter.default.post(name: .cassetteFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
#endif
