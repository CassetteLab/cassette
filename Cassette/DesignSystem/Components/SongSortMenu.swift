// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The sort control for the All Songs list: a menu listing the `SongSort` options with a checkmark on the
/// active one. Bound to the caller's persisted `@AppStorage("cassette.songSort")`.
struct SongSortMenu: View {
    @Binding var sort: SongSort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(SongSort.allCases, id: \.self) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Label(sort.label, systemImage: "arrow.up.arrow.down")
        }
    }
}
