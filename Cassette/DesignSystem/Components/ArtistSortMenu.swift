// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The sort control for the artists list, bound to the caller's persisted `@AppStorage("cassette.artistSort")`.
struct ArtistSortMenu: View {
    @Binding var sort: ArtistSort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(ArtistSort.allCases, id: \.self) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Label(sort.label, systemImage: "arrow.up.arrow.down")
        }
    }
}
