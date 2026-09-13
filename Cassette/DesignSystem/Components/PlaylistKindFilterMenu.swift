// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftUI

/// Chooses which kinds of playlist the playlist list shows.
///
/// The four kinds are different things rather than variants of one, so this is a set of checkboxes
/// and not a picker: someone may want their own server playlists without the generated noise, or
/// only the generated ones. The choice is persisted per server and survives a relaunch.
///
/// One `Menu` works on both platforms — a `Toggle` inside it renders as a checked row on macOS and
/// as a checkmarked row on iOS — so there is no per-platform variant to keep in step.
struct PlaylistKindFilterMenu: View {
    @Environment(\.appContainer) private var container

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }
    private var hidden: Set<PlaylistKind> { activeServer?.hiddenPlaylistKindSet ?? [] }

    /// At least one kind is hidden. Worth saying out loud in the chrome: a filter the user set on
    /// another launch is otherwise indistinguishable from playlists that have gone missing.
    private var isFiltering: Bool { !hidden.isEmpty }

    var body: some View {
        Menu {
            Section("Show") {
                ForEach(PlaylistKind.displayOrder) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Text(String(localized: kind.title))
                    }
                    .disabled(PlaylistKind.isLastVisible(kind, hidden: hidden))
                }
            }
        } label: {
            Image(systemName: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .foregroundStyle(Color.cassetteAccent)
        }
        .accessibilityLabel(Text("Filter Playlists"))
        .accessibilityValue(Text(isFiltering ? "Filter active" : "All types shown"))
    }

    private func binding(for kind: PlaylistKind) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(kind) },
            set: { shown in
                var next = hidden
                if shown { next.remove(kind) } else { next.insert(kind) }
                guard next != hidden else { return }
                Task { await apply(next) }
            }
        )
    }

    /// Persists the choice. The list redraws from what it already has — nothing is refetched, and
    /// nothing is written to the server: hiding a playlist is not deleting it.
    private func apply(_ next: Set<PlaylistKind>) async {
        guard let container, let serverId = activeServer?.id else { return }
        do {
            try await container.serverService.setHiddenPlaylistKinds(serverId: serverId, kinds: next)
        } catch {
            Logger.playlist.error("[PLAYLIST] could not change the type filter: \(error, privacy: .public)")
            container.toastService.showError(String(localized: "Couldn't change the filter. Please try again."))
        }
    }
}
