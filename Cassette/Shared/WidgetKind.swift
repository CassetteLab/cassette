// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Widget kind identifiers shared between the app and widget extension.
nonisolated enum WidgetKind {
    static let nowPlaying = "NowPlayingWidget"
    static let pinned = "PinnedWidget"
}
