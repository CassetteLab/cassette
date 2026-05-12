// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import WidgetKit
import SwiftUI

struct RecentlyPlayedWidget: Widget {
    let kind = "RecentlyPlayedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentlyPlayedProvider()) { entry in
            RecentlyPlayedWidgetView(entry: entry)
        }
        .configurationDisplayName("Écoutés récemment")
        .description("Affiche le dernier morceau écouté.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentlyPlayedWidgetView: View {
    let entry: RecentlyPlayedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            RecentlyPlayedMediumView(entry: entry)
        default:
            RecentlyPlayedSmallView(entry: entry)
        }
    }
}
