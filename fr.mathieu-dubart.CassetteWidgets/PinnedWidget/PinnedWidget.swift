// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import WidgetKit
import SwiftUI

struct PinnedWidget: Widget {
    let kind = "PinnedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedProvider()) { entry in
            PinnedWidgetView(entry: entry)
        }
        .configurationDisplayName("Éléments épinglés")
        .description("Accédez rapidement à vos éléments épinglés.")
        .supportedFamilies([.systemMedium])
    }
}

struct PinnedWidgetView: View {
    let entry: PinnedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        default:
            PinnedMediumView(entry: entry)
        }
    }
}
