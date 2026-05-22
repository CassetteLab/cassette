// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

extension Notification.Name {
    static let cassetteTogglePlayPause = Notification.Name("cassette.togglePlayPause")
    static let cassetteSkipNext = Notification.Name("cassette.skipNext")
    static let cassetteSkipPrevious = Notification.Name("cassette.skipPrevious")
    static let cassetteFocusSearch = Notification.Name("cassette.focusSearch")
    static let cassetteToggleShuffle = Notification.Name("cassette.toggleShuffle")
    static let cassetteToggleRepeat = Notification.Name("cassette.toggleRepeat")
    static let cassetteToggleQueue = Notification.Name("cassette.toggleQueue")
    static let cassetteOpenFullPlayer = Notification.Name("cassette.openFullPlayer")
    static let cassetteOpenFullPlayerLyrics = Notification.Name("cassette.openFullPlayerLyrics")
    static let cassetteSelectAlbums = Notification.Name("cassette.selectAlbums")
}
