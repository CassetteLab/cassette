// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Color tokens
//
// cassetteAccent and cassetteAccentSecondary are generated automatically by Xcode
// from Assets.xcassets. Do not redeclare them here.
//
// Usage rules:
//   cassetteAccent          → primary interactive actions only: Play button, scrubber progress,
//                             active shuffle/repeat toggles, tappable artist name.
//                             Contrast: ~3.5:1 on white (AA for large text / icons only).
//                             Never use for body copy, captions, or informational labels.
//   cassetteAccentSecondary → gradient stop alongside cassetteAccent, subtle tinted backgrounds.
//                             Not for text.
//
//   All other text and background colors delegate to SwiftUI / UIKit semantic colors
//   (Color.primary, Color.secondary, Color(.systemBackground), etc.) which adapt
//   to light/dark mode automatically without any custom asset.

extension Color {
    /// White — for text/icons placed on a cassetteAccent-filled surface.
    static let cassetteAccentText = Color.white

    /// Shadow color for cover art in light mode.
    static let cassetteCoverShadow = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.15)

    /// Thin border for cover art in dark mode, replacing the invisible shadow.
    static let cassetteCoverBorder = Color.white.opacity(0.08)
}
