// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Circle placeholder for an artist with no available photo.
/// Uses a deterministic HSB gradient derived from the artist name, with the artist's initials centred on top.
struct ArtistPlaceholderView: View {
    let name: String
    let size: CGFloat

    private static let gradientPairs: [(Color, Color)] = [
        (Color(hue: 0.60, saturation: 0.55, brightness: 0.75), Color(hue: 0.70, saturation: 0.60, brightness: 0.55)),
        (Color(hue: 0.08, saturation: 0.70, brightness: 0.85), Color(hue: 0.02, saturation: 0.65, brightness: 0.60)),
        (Color(hue: 0.35, saturation: 0.55, brightness: 0.70), Color(hue: 0.42, saturation: 0.60, brightness: 0.50)),
        (Color(hue: 0.75, saturation: 0.50, brightness: 0.80), Color(hue: 0.82, saturation: 0.55, brightness: 0.55)),
        (Color(hue: 0.52, saturation: 0.60, brightness: 0.72), Color(hue: 0.57, saturation: 0.65, brightness: 0.52)),
        (Color(hue: 0.14, saturation: 0.65, brightness: 0.88), Color(hue: 0.10, saturation: 0.70, brightness: 0.62)),
        (Color(hue: 0.92, saturation: 0.50, brightness: 0.80), Color(hue: 0.97, saturation: 0.55, brightness: 0.58)),
        (Color(hue: 0.45, saturation: 0.45, brightness: 0.75), Color(hue: 0.50, saturation: 0.50, brightness: 0.55)),
    ]

    private var gradientPair: (Color, Color) {
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return Self.gradientPairs[hash % Self.gradientPairs.count]
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [gradientPair.0, gradientPair.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.35, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}
