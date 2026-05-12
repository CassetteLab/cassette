// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Stable cross-process DTO for the current now-playing state.
/// Never rename fields — UserDefaults persists JSON between app and widget processes.
nonisolated struct SharedNowPlayingState: Codable, Hashable, Sendable {
    let track: SharedTrackInfo?
    let isPlaying: Bool
    let lastUpdated: Date
}
