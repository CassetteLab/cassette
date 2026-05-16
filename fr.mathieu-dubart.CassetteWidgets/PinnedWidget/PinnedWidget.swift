// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import WidgetKit
import SwiftUI

#if os(iOS)
struct PinnedWidget: Widget {
    let kind = WidgetKind.pinned

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedProvider()) { entry in
            PinnedWidgetView(entry: entry)
        }
        .configurationDisplayName("Éléments épinglés")
        .description("Accédez rapidement à vos éléments épinglés.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PinnedWidgetView: View {
    let entry: PinnedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemLarge:
            PinnedLargeView(entry: entry)
        default:
            PinnedMediumView(entry: entry)
        }
    }
}
#endif
