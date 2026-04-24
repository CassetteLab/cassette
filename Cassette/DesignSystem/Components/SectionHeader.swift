// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Section label in SF Pro Rounded semibold. Use above lists or grids in detail screens.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.cassetteSectionTitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.vertical, CassetteSpacing.s)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "Albums")
        SectionHeader(title: "Top Tracks")
    }
}
