// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Apple-Music-style circular toolbar action label: accent-filled with a white glyph when active, a subtle
/// grey circle otherwise (cancel / disabled). Shared by the playlist edit + add-music sheets so their X / ✓
/// read identically. Cross-platform.
struct CircleToolbarLabel: View {
    let systemName: String
    var filled: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Color.primary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(filled ? Color.cassetteAccent : Color.secondary.opacity(0.15)))
    }
}
