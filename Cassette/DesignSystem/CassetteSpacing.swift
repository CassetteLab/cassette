// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
    static let large: CGFloat    = 12   // full-player cover art, sheets
    static let pill: CGFloat     = 999  // capsule buttons
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
