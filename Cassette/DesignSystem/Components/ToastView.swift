// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Toast view

struct ToastView: View {
    let toast: ToastService.Toast

    var body: some View {
        HStack(spacing: CassetteSpacing.s) {
            leading

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.message)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.leading)

            // Chevron only when the toast is tappable (e.g. add-to-playlist → opens the playlist).
            if toast.action != nil {
                Image(systemName: "chevron.forward")
                    .font(.cassetteCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, CassetteSpacing.s)
            }
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(.regularMaterial)
        )
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, CassetteSpacing.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Leading element: the cover thumbnail (Apple-Music pill) when the toast carries a `coverArtId`,
    /// otherwise the style icon so plain confirmations (e.g. "Pinned to Home") keep their look.
    @ViewBuilder
    private var leading: some View {
        if let coverArtId = toast.coverArtId {
            CoverArtView(id: coverArtId, size: 120)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard))
        } else {
            Image(systemName: toast.style.systemImage)
                .foregroundStyle(toast.style.tint)
        }
    }
}

// MARK: - Overlay modifier

struct ToastOverlay: ViewModifier {
    @Environment(ToastService.self) private var toastService
    @Environment(\.appContainer) private var container

    /// Mirrors MainTabView.hasTrack — true while the mini player bar is on screen.
    private var miniPlayerVisible: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    /// Bottom inset so the toast floats just above the mini player when it is shown, otherwise just
    /// above the tab bar / home indicator. Tunable if the gap needs nudging on device.
    private var bottomInset: CGFloat {
        #if os(iOS)
        miniPlayerVisible ? CassetteSpacing.miniPlayerBottomMargin + CassetteSpacing.s : CassetteSpacing.l
        #else
        miniPlayerVisible ? CassetteMacOSLayout.playerBarReservedHeight + CassetteSpacing.s : CassetteSpacing.l
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = toastService.current {
                    ToastView(toast: toast)
                        .padding(.bottom, bottomInset)
                        .id(toast.id)
                        // Only tappable toasts intercept touches; plain ones stay non-interactive so
                        // taps pass through to the content underneath (unchanged behaviour).
                        .allowsHitTesting(toast.action != nil)
                        .onTapGesture { handleTap(toast) }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastService.current)
    }

    /// Resolves a tappable toast: dismiss it, then navigate via the existing notification pattern
    /// (same path as `.cassetteNavigateToArtist`) — no new navigation channel is introduced.
    private func handleTap(_ toast: ToastService.Toast) {
        guard let action = toast.action else { return }
        toastService.dismiss()
        switch action {
        case let .navigateToPlaylist(id, name, coverArtId):
            postNavigateToPlaylist(playlistId: id, name: name, coverArtId: coverArtId)
        }
    }
}

extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
