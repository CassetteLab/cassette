// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Credits Ko-fi supporters by name: one row each, in the order they joined, with no amount,
/// tier or ranking. Hidden while the list is empty.
struct SupportersSection: View {
    var supporters: [Supporter] = SupportersList.bundled

    var body: some View {
        if !supporters.isEmpty {
            Section {
                ForEach(supporters.indices, id: \.self) { index in
                    // Verbatim: a chosen name is neither a localization key nor Markdown.
                    Text(verbatim: supporters[index].name)
                }
            } header: {
                Text("Supporters")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Thank you to everyone who supports Cassette on Ko-fi. Only public supporters are listed.")
            }
        }
    }
}
