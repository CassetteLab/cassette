// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The gradient "forms" a user can pick for a generated playlist cover (Apple-Music direction). A form is a
/// geometry/treatment only — the COLOR follows the playlist's content (the first track's dominant color), so
/// every playlist's gradient is unique to its music. Cross-platform (Phase 5 macOS reuses these as-is).
enum PlaylistGradientShape: String, CaseIterable, Codable, Sendable, Identifiable {
    case verticalFade
    case diagonalSheen
    case radialGlow
    case angularSweep
    case duotone
    case mesh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .verticalFade:  return "Fade"
        case .diagonalSheen: return "Sheen"
        case .radialGlow:    return "Glow"
        case .angularSweep:  return "Sweep"
        case .duotone:       return "Duotone"
        case .mesh:          return "Mesh"
        }
    }
}

/// A frozen gradient-cover spec: the chosen form + the resolved base color (the first track's dominant color
/// at creation time). FROZEN — the base color is stored, never re-derived live, so the cover does not drift
/// if the first track later changes. Codable for the SwiftData store; the gradient is rendered from this.
struct PlaylistGradientSpec: Codable, Equatable, Sendable {
    var shape: PlaylistGradientShape
    var red: Double
    var green: Double
    var blue: Double

    var baseColor: Color { Color(red: red, green: green, blue: blue) }

    init(shape: PlaylistGradientShape, baseColor: Color) {
        self.shape = shape
        let rgb = baseColor.rgbComponents ?? (0.30, 0.32, 0.40)
        self.red = rgb.red
        self.green = rgb.green
        self.blue = rgb.blue
    }

    /// Neutral default for an empty playlist (no first track to derive a color from yet) — a calm slate.
    /// Marked elsewhere as a *system* default (not a user pick), so a real choice never gets overwritten.
    static func neutral(shape: PlaylistGradientShape = .verticalFade) -> PlaylistGradientSpec {
        PlaylistGradientSpec(shape: shape, baseColor: Color(red: 0.30, green: 0.32, blue: 0.40))
    }
}

/// Renders a `PlaylistGradientSpec` as a SwiftUI view — used for the picker preview and (off-screen) for the
/// JPEG render that becomes the real cover. Switches on the form; each derives its stops from the one base
/// color via `Color.adjusted`. Cross-platform; the mesh form falls back to a linear gradient pre-iOS 18.
struct PlaylistGradientView: View {
    let spec: PlaylistGradientSpec

    var body: some View {
        let base = spec.baseColor
        let light = base.adjusted(saturation: -0.04, brightness: 0.18)
        let dark = base.adjusted(saturation: 0.06, brightness: -0.24)

        switch spec.shape {
        case .verticalFade:
            LinearGradient(colors: [light, base, dark], startPoint: .top, endPoint: .bottom)
        case .diagonalSheen:
            LinearGradient(colors: [light, base, dark], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .radialGlow:
            RadialGradient(colors: [light, base, dark], center: .center, startRadius: 0, endRadius: 360)
        case .angularSweep:
            AngularGradient(colors: [base, light, base.adjusted(hue: 0.08), dark, base], center: .center)
        case .duotone:
            LinearGradient(
                colors: [base, base.adjusted(hue: 0.10, brightness: -0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .mesh:
            meshOrFallback(base: base, light: light, dark: dark)
        }
    }

    @ViewBuilder
    private func meshOrFallback(base: Color, light: Color, dark: Color) -> some View {
        if #available(iOS 18, macOS 15, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: [
                    light, base, light,
                    base, base.adjusted(hue: 0.05), dark,
                    dark, base, dark,
                ]
            )
        } else {
            LinearGradient(colors: [light, base, dark], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
