// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import WidgetKit
import SwiftUI

struct RecentlyPlayedWidget: Widget {
    let kind = "RecentlyPlayedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentlyPlayedProvider()) { _ in
            Text("Recently Played")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Écoutés récemment")
        .description("Affiche le dernier morceau que vous avez écouté.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

nonisolated struct RecentlyPlayedEntry: TimelineEntry {
    let date: Date

    static var placeholder: RecentlyPlayedEntry { RecentlyPlayedEntry(date: Date()) }
}

struct RecentlyPlayedProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentlyPlayedEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (RecentlyPlayedEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentlyPlayedEntry>) -> Void) {
        completion(Timeline(entries: [.placeholder], policy: .never))
    }
}
