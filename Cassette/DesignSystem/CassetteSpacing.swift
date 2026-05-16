// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Spacing scale (4pt grid)

enum CassetteSpacing {
    static let xs: CGFloat    = 4
    static let s: CGFloat     = 8
    static let m: CGFloat     = 12
    static let l: CGFloat     = 16   // default horizontal screen padding
    static let xl: CGFloat    = 20
    static let xxl: CGFloat   = 24   // between sections
    static let xxxl: CGFloat  = 32
    static let xxxxl: CGFloat = 48
}

// MARK: - Corner radius scale

enum CassetteCornerRadius {
    static let xs: CGFloat       = 4
    static let s: CGFloat        = 6
    static let standard: CGFloat = 8    // all cover arts, most cards
    static let large: CGFloat     = 12   // full-player cover art, sheets
    static let hero: CGFloat      = 20   // Wrapped stat hero, year card
    static let pill: CGFloat      = 999  // capsule buttons
}

// MARK: - Shadow presets

/// Cassette shadow values. In dark mode, shadows are invisible against black backgrounds;
/// use `CassetteCoverModifier` (via `.cassetteCoverStyle()`) which switches to a thin
/// border in dark mode automatically.
enum CassetteShadow {
    static let coverRadius: CGFloat  = 8
    static let coverY: CGFloat       = 4
    static let coverOpacity: Double  = 0.15
}

// MARK: - View modifier: content width (macOS)

/// Constrains content to a max width on macOS so iPhone-designed layouts don't stretch
/// grotesquely in wide windows. On iOS this is a no-op.
struct ContentWidthModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        #else
        content
        #endif
    }
}

extension View {
    func cassetteContentWidth() -> some View {
        modifier(ContentWidthModifier())
    }
}

// MARK: - View modifier: cover art style

struct CassetteCoverModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: colorScheme == .dark ? .clear : Color.cassetteCoverShadow,
                radius: CassetteShadow.coverRadius,
                y: CassetteShadow.coverY
            )
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.cassetteCoverBorder, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Clips to a rounded rectangle, adds shadow in light mode and a thin border in dark mode.
    func cassetteCoverStyle(cornerRadius: CGFloat = CassetteCornerRadius.standard) -> some View {
        modifier(CassetteCoverModifier(cornerRadius: cornerRadius))
    }
}
