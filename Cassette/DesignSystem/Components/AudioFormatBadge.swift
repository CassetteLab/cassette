// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct AudioFormatBadge: View {
    let format: String

    var body: some View {
        Text(format)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.cassetteAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .strokeBorder(Color.cassetteAccent.opacity(0.5), lineWidth: 1)
            )
    }
}
