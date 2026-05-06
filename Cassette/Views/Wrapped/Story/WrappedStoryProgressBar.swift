// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Segmented progress bar shown at the top of the story player.
/// Segments before `currentIndex` are fully filled; the current segment
/// fills proportionally to `progress` (0…1); subsequent segments are empty.
struct WrappedStoryProgressBar: View {
    let totalSlides: Int
    let currentIndex: Int
    let progress: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<totalSlides, id: \.self) { index in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * segmentFill(for: index))
                    }
                }
                .frame(height: 2.5)
            }
        }
    }

    private func segmentFill(for index: Int) -> Double {
        if index < currentIndex { return 1.0 }
        if index == currentIndex { return max(0, min(1, progress)) }
        return 0.0
    }
}
