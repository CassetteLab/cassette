// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import WidgetKit
import SwiftUI

@main
struct CassetteWidgetsBundle: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        NowPlayingWidget()
        PinnedWidget()
        #endif
    }
}
