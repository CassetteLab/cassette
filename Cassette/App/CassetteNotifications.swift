// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

extension Notification.Name {
    static let cassetteTogglePlayPause = Notification.Name("cassette.togglePlayPause")
    static let cassetteSkipNext = Notification.Name("cassette.skipNext")
    static let cassetteSkipPrevious = Notification.Name("cassette.skipPrevious")
    static let cassetteFocusSearch = Notification.Name("cassette.focusSearch")
    static let cassetteToggleShuffle = Notification.Name("cassette.toggleShuffle")
    static let cassetteToggleRepeat = Notification.Name("cassette.toggleRepeat")
}
