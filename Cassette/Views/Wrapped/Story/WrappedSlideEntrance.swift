// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Entrance animation for Wrapped story slide content.
/// Drifts upward on appear; respects Reduce Motion (instant appear, no drift).
struct WrappedSlideEntrance: ViewModifier {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: appeared || reduceMotion ? 0 : 24)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.1)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func wrappedSlideEntrance() -> some View {
        modifier(WrappedSlideEntrance())
    }
}
