// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Closure wired by AppContainer.init so PlayPauseIntent can invoke the player
/// without importing AppContainer into the widget extension compile scope.
nonisolated enum NowPlayingBridge {
    nonisolated(unsafe) static var performTogglePlayPause: (@Sendable () async -> Void)?
}
