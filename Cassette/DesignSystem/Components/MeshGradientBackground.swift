// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Reusable mesh gradient background derived from a 3-color palette.
/// Falls back to LinearGradient on macOS 14 where MeshGradient is unavailable.
struct MeshGradientBackground: View {
    /// 3 colors from WrappedYearPalette.
    let palette: [Color]
    /// When true, subtly animates mesh control points (8s period, ±0.04 amplitude).
    let animated: Bool

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        gradient
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    animationPhase = 1
                }
            }
    }

    @ViewBuilder
    private var gradient: some View {
        if #available(iOS 18, macOS 15, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: currentPoints,
                colors: distributedColors
            )
        } else {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var currentPoints: [SIMD2<Float>] {
        let p = Float(animationPhase)
        return [
            [0.0, 0.0], [0.5 + 0.04 * p, 0.0],                        [1.0, 0.0],
            [0.0, 0.5 + 0.03 * p], [0.5 - 0.04 * p, 0.5 + 0.04 * p], [1.0, 0.5 - 0.03 * p],
            [0.0, 1.0], [0.5 + 0.03 * p, 1.0],                        [1.0, 1.0]
        ]
    }

    // Diagonal sweep: c0 top-left → c1 center → c2 bottom-right
    private var distributedColors: [Color] {
        guard palette.count >= 3 else {
            return Array(repeating: palette.first ?? .clear, count: 9)
        }
        let c0 = palette[0], c1 = palette[1], c2 = palette[2]
        return [c0, c0, c1,
                c0, c1, c1,
                c1, c2, c2]
    }
}
