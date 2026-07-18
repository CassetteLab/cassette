// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import WidgetKit
import SwiftUI

#if os(iOS)
struct NowPlayingWidget: Widget {
    let kind = WidgetKind.nowPlaying

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Displays the currently playing track.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            NowPlayingMediumView(entry: entry)
        default:
            NowPlayingSmallView(entry: entry)
        }
    }
}
#endif
