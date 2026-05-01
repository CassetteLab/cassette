// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Toast view

struct ToastView: View {
    let toast: ToastService.Toast

    var body: some View {
        HStack(spacing: CassetteSpacing.s) {
            Image(systemName: toast.style.systemImage)
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(.cassetteCellTitle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, CassetteSpacing.l)
        .padding(.vertical, CassetteSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                .stroke(toast.style.tint.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, CassetteSpacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
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
