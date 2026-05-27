// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(iOS)
private struct TrackSkipSwipeModifier: ViewModifier {
    @Environment(\.appContainer) private var container
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingSwipe = false

    let playerState: PlayerState

    private let swipeThreshold: CGFloat = 80
    private let velocityThreshold: CGFloat = 200

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .opacity(1.0 - min(abs(dragOffset) / 200, 0.4))
            .gesture(swipeGesture)
            .onChange(of: playerState.currentTrack?.id) { _, _ in dragOffset = 0 }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimatingSwipe, !playerState.isLiveStream else { return }
                let h = value.translation.width
                guard abs(h) > abs(value.translation.height) else { return }
                withAnimation(.interactiveSpring()) { dragOffset = h }
            }
            .onEnded { value in
                guard !isAnimatingSwipe, !playerState.isLiveStream else { return }
                let h = value.translation.width
                let velocity = value.velocity.width
                guard abs(h) > abs(value.translation.height) else { bounceBack(); return }
                let triggeredNext = h < -swipeThreshold || velocity < -velocityThreshold
                let triggeredPrev = h > swipeThreshold || velocity > velocityThreshold
                if triggeredNext || triggeredPrev {
                    commitSwipe(goNext: triggeredNext)
                } else {
                    bounceBack()
                }
            }
    }

    private func commitSwipe(goNext: Bool) {
        isAnimatingSwipe = true
        HapticFeedback.medium.trigger()
        withAnimation(.easeIn(duration: 0.18)) { dragOffset = goNext ? -300 : 300 }
        Task {
            if goNext {
                try? await container?.playerService.skipToNext()
            } else {
                try? await container?.playerService.skipToPrevious()
            }
            await MainActor.run {
                dragOffset = goNext ? 300 : -300
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = 0 }
                isAnimatingSwipe = false
            }
        }
    }

    private func bounceBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = 0 }
    }
}
#endif

extension View {
    func trackSkipSwipe(playerState: PlayerState) -> some View {
        #if os(iOS)
        modifier(TrackSkipSwipeModifier(playerState: playerState))
        #else
        self
        #endif
    }
}
