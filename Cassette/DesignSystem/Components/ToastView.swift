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
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .stroke(toast.style.tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, CassetteSpacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
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

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastService.current {
                    ToastView(toast: toast)
                        .padding(.top, CassetteSpacing.s)
                        .id(toast.id)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastService.current)
    }
}

extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
