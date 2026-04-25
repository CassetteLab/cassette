// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Uniform empty-state placeholder for list and search screens.
///
/// Usage examples:
/// ```swift
/// EmptyStateView(systemImage: "music.mic", title: "No Artists")
/// EmptyStateView(systemImage: "wifi.slash", title: "You're Offline",
///                subtitle: "Downloaded content is still available.",
///                action: .init(label: "Retry") { Task { await vm.load() } })
/// ```
struct EmptyStateView: View {
    struct Action {
        let label: String
        let handler: () -> Void
    }

    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var action: Action? = nil

    var body: some View {
        VStack(spacing: CassetteSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: CassetteSpacing.s) {
                Text(title)
                    .font(.cassetteSectionTitle)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.cassetteBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }

            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cassetteAccent)
            }
        }
        .padding(CassetteSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("With action") {
    EmptyStateView(
        systemImage: "magnifyingglass",
        title: "No Results",
        subtitle: "Try a different search term.",
        action: .init(label: "Clear") {}
    )
}

#Preview("Minimal") {
    EmptyStateView(systemImage: "arrow.down.circle", title: "No Downloads")
        .preferredColorScheme(.dark)
}
