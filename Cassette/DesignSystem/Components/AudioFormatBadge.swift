// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct AudioFormatBadge: View {
    let format: String
    var color: Color = Color.cassetteAccent

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .strokeBorder(color.opacity(0.5), lineWidth: 1)
            )
            .accessibilityLabel(format)
    }
}
