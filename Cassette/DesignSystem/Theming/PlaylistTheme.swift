// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Cross-platform color palette for the playlist rebrand (Apple-Music direction) — the keystone of the
/// theming system, reused across every playlist surface and BOTH platforms (deliberately no `#if os`).
///
/// The color SOURCE is pluggable: Phase 1 feeds the playlist cover's dominant color (`fromCover`); Phase 2
/// will derive a color from the chosen gradient / first track and feed it straight into
/// `init(dominantColor:)`. The engine only consumes the resolved theme color and produces the adaptive
/// foreground palette; `PlaylistThemedBackground` consumes the same theme for the blended background.
struct PlaylistTheme: Equatable, Sendable {
    /// Base theme color. `.clear` = not resolved yet → system-adaptive fallback (no blend).
    let dominantColor: Color

    init(dominantColor: Color) {
        self.dominantColor = dominantColor
    }

    var isThemed: Bool { dominantColor != .clear }
    var isLight: Bool { isThemed && dominantColor.luminance > 0.6 }

    // Adaptive foreground over the themed background. `isLight` uses the app-wide PERCEIVED (BT.601)
    // luminance (`Color.luminance > 0.6`) — the same light/dark convention as the full player, and the
    // Apple-Music-correct bias toward white text (dark text only on clearly light covers). The `accentColor`
    // below uses a separate WCAG contrast check — an accessibility concern for the accent specifically, NOT a
    // competing isLight definition; these two are intentionally distinct, not a duplication to unify.
    // System-adaptive (`.primary`/`.secondary`) until the theme color resolves.
    var contentColor: Color { isThemed ? (isLight ? .black : .white) : .primary }
    var secondaryContentColor: Color {
        isThemed ? (isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.7)) : .secondary
    }
    var tertiaryContentColor: Color {
        isThemed ? (isLight ? Color.black.opacity(0.5) : Color.white.opacity(0.5)) : Color.secondary.opacity(0.6)
    }
    var glassTint: Color { isLight ? Color.black.opacity(0.1) : Color.white.opacity(0.15) }

    /// Contrast-correct accent for active controls / highlights against the theme background — reuses the
    /// app-wide `ColorContrastUtils` WCAG path so accents stay legible on any cover.
    var accentColor: Color { CassetteColors.accentForeground(on: dominantColor) }

    /// Not-yet-resolved theme (system-adaptive foreground, no blend).
    static let unthemed = PlaylistTheme(dominantColor: .clear)

    /// Phase-1 color source: derive the theme from a playlist cover via `DominantColorExtractor`.
    /// Returns `.unthemed` when the color isn't cached yet (callers can drive an async first-load
    /// extraction separately and re-construct). Phase 2 plugs a different source into `init(dominantColor:)`.
    @MainActor
    static func fromCover(coverArtId: String?, image: PlatformImage?, using extractor: DominantColorExtractor) -> PlaylistTheme {
        guard let coverArtId else { return .unthemed }
        return PlaylistTheme(dominantColor: extractor.dominantColor(for: coverArtId, image: image))
    }
}
