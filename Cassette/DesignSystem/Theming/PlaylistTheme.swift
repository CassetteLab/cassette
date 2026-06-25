// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Cross-platform colour palette for the themed detail surfaces (Apple-Music direction) — reused across the
/// playlist / album / artist heroes and BOTH platforms (deliberately no `#if os`). It wraps a single resolved
/// `dominantColor` and produces the adaptive foreground palette; `PlaylistThemedBackground` consumes the same
/// theme for the blended background.
struct PlaylistTheme: Equatable, Sendable {
    /// Base theme color. `.clear` = not resolved yet → system-adaptive fallback (no blend).
    let dominantColor: Color

    init(dominantColor: Color) {
        self.dominantColor = dominantColor
    }

    var isThemed: Bool { dominantColor != .clear }
    var isLight: Bool { isThemed && dominantColor.luminance > 0.6 }

    // Adaptive foreground over the themed background. `isLight` uses the app-wide PERCEIVED (BT.601) luminance
    // (`Color.luminance > 0.6`) — the same light/dark convention as the full player, and the Apple-Music-correct
    // bias toward white text (dark text only on clearly light covers). System-adaptive (`.primary`/`.secondary`)
    // until the theme color resolves.
    var contentColor: Color { isThemed ? (isLight ? .black : .white) : .primary }
    var secondaryContentColor: Color {
        isThemed ? (isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.7)) : .secondary
    }
}
