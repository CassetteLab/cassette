// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Visual identity of each mood, in one place so the generated playlist cover and anything else
/// showing a mood agree on its colour.
extension Mood {
    /// Signature colour. Chosen dark enough that the white glyph and title the gradient renderer
    /// draws over it stay legible.
    var baseColor: Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .night:     return (0.16, 0.18, 0.42)
        case .energetic: return (0.85, 0.33, 0.12)
        case .workout:   return (0.72, 0.11, 0.28)
        case .chill:     return (0.11, 0.45, 0.42)
        case .focus:     return (0.20, 0.30, 0.48)
        }
    }

    /// Cover generated for this mood's server playlist. A distinct gradient shape per mood so the
    /// five are told apart at thumbnail size, where the colours alone are too close to read.
    var gradientSpec: PlaylistGradientSpec {
        let shape: PlaylistGradientShape
        switch self {
        case .night:     shape = .radialGlow
        case .energetic: shape = .angularSweep
        case .workout:   shape = .diagonalSheen
        case .chill:     shape = .verticalFade
        case .focus:     shape = .mesh
        }
        return PlaylistGradientSpec(shape: shape, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
