// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// The ordered set of slides shown in the annual Wrapped story player.
nonisolated enum WrappedStorySlideKind: String, CaseIterable, Sendable {
    case intro        = "Intro"
    case minutes      = "Minutes"
    case topTrack     = "Top Track"
    case topArtist    = "Top Artist"
    case topAlbum     = "Top Album"
    case topGenre     = "Top Genre"
    case discoveries  = "Discoveries"
    case closing      = "Closing"
}
