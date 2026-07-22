// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(iOS)
/// Reserves bottom scroll-content space so the mini player never overlaps the last, tappable rows.
///
/// The space needed differs by OS, because the mini player is hosted differently:
/// - **iOS 26**: the system `tabViewBottomAccessory` already extends the scroll safe area, so most
///   scroll views need nothing. Only edge-to-edge detail views whose content bleeds under it
///   (`bleedsToBottom`) reserve extra breathing room.
/// - **iOS 18**: the mini player is hosted via `safeAreaInset` on the `TabView`, which does NOT
///   extend the *scroll* safe area — so EVERY scrollable screen must reserve the space itself.
///
/// Mirrors `MainTabView.hasTrack` so the margin only exists while the bar is shown.
private struct MiniPlayerBottomMargin: ViewModifier {
    @Environment(\.appContainer) private var container
    let bleedsToBottom: Bool

    private var isMiniPlayerVisible: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if bleedsToBottom {
                content
                    .contentMargins(.bottom, isMiniPlayerVisible ? CassetteSpacing.miniPlayerBottomMargin : 0, for: .scrollContent)
            } else {
                // The system accessory already reserves scroll safe area; a margin would over-space.
                content
            }
        } else {
            // iOS 18: the safeAreaInset host reserves no scroll space, so reserve it here for every view.
            content
                .contentMargins(.bottom, isMiniPlayerVisible ? CassetteSpacing.miniPlayerBottomMargin : 0, for: .scrollContent)
        }
    }
}
#endif

extension View {
    /// Reserves bottom scroll space so the mini player never covers the last rows (iOS only; no-op on macOS).
    ///
    /// - Parameter bleedsToBottom: pass `true` for edge-to-edge detail views whose content scrolls under
    ///   the mini player on iOS 26 too (e.g. album / playlist detail). Plain lists leave it `false` — they
    ///   only need the margin on iOS 18.
    @ViewBuilder
    func miniPlayerBottomMargin(bleedsToBottom: Bool = false) -> some View {
        #if os(iOS)
        modifier(MiniPlayerBottomMargin(bleedsToBottom: bleedsToBottom))
        #else
        self
        #endif
    }
}
