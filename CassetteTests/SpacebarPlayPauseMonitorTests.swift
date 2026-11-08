// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import AppKit
import Testing
@testable import Cassette

@Suite("Spacebar play/pause monitor")
struct SpacebarPlayPauseMonitorTests {
    @MainActor
    @Test("bare Space posts the play/pause notification")
    func bareSpacePostsPlayPause() throws {
        let coordinator = SpacebarPlayPauseMonitorView.Coordinator()
        coordinator.start()
        defer { coordinator.stop() }

        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .cassetteTogglePlayPause,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                counter.count += 1
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        NSApp.sendEvent(event)

        #expect(counter.count == 1)
    }
}

@MainActor
private final class NotificationCounter {
    var count = 0
}
#endif
