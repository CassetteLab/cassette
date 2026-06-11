// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(iOS)
/// Reserves bottom scroll-content space for the floating tabViewBottomAccessory
/// mini player, which overlays tab content without extending the safe area.
/// Mirrors MainTabView.hasTrack so the margin only exists while the bar is shown.
private struct MiniPlayerBottomMargin: ViewModifier {
    @Environment(\.appContainer) private var container

    private var isMiniPlayerVisible: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, isMiniPlayerVisible ? CassetteSpacing.miniPlayerBottomMargin : 0, for: .scrollContent)
    }
}
#endif

extension View {
    /// Adds bottom scroll margin matching the mini player accessory (iOS only; no-op on macOS).
    @ViewBuilder
    func miniPlayerBottomMargin() -> some View {
        #if os(iOS)
        modifier(MiniPlayerBottomMargin())
        #else
        self
        #endif
    }
}
