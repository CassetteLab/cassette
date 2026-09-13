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
/// The control stays open across taps, so hiding two kinds is two taps and not two trips: on iOS
/// that is a `Menu` told not to dismiss, and on macOS a popover, because an AppKit menu always
/// closes on selection and `menuActionDismissBehavior(.disabled)` is unavailable there. The
/// checkbox list itself is shared, so only the container differs.
struct PlaylistKindFilterMenu: View {
    @Environment(\.appContainer) private var container
    #if os(macOS)
    @State private var isPresented = false
    #endif

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }
    private var hidden: Set<PlaylistKind> { activeServer?.hiddenPlaylistKindSet ?? [] }

    /// At least one kind is hidden. Worth saying out loud in the chrome: a filter the user set on
    /// another launch is otherwise indistinguishable from playlists that have gone missing.
    private var isFiltering: Bool { !hidden.isEmpty }

    var body: some View {
        control
            .accessibilityLabel(Text("Filter Playlists"))
            .accessibilityValue(Text(isFiltering ? "Filter active" : "All types shown"))
    }

    @ViewBuilder
    private var control: some View {
        #if os(macOS)
        Button { isPresented.toggle() } label: { icon }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                    Text("Show")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                    checkboxes
                }
                .padding(CassetteSpacing.m)
            }
        #else
        Menu {
            Section("Show") { checkboxes }
        } label: {
            icon
        }
        // Checkboxes, not a picker: hiding two kinds is one decision, and a menu that closed on the
        // first tick would make the user reopen it for every one of them.
        .menuActionDismissBehavior(.disabled)
        #endif
    }

    @ViewBuilder
    private var checkboxes: some View {
        ForEach(PlaylistKind.displayOrder) { kind in
            Toggle(isOn: binding(for: kind)) {
                Text(String(localized: kind.title))
            }
            .disabled(PlaylistKind.isLastVisible(kind, hidden: hidden))
        }
    }

    private var icon: some View {
        Image(systemName: isFiltering
              ? "line.3.horizontal.decrease.circle.fill"
              : "line.3.horizontal.decrease.circle")
            .foregroundStyle(Color.cassetteAccent)
    }

    private func binding(for kind: PlaylistKind) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(kind) },
            set: { shown in
                guard shown == hidden.contains(kind) else { return }
                Task { await apply(kind, isHidden: !shown) }
            }
        )
    }

    /// Persists one checkbox. Sends the single change rather than the whole set: the menu stays
    /// open, so a second tap can land while the first is still being written, and a whole-set write
    /// computed from the set this view last rendered would undo it.
    ///
    /// The list redraws from what it already has — nothing is refetched, and nothing is written to
    /// the server: hiding a playlist is not deleting it.
    private func apply(_ kind: PlaylistKind, isHidden: Bool) async {
        guard let container, let serverId = activeServer?.id else { return }
        do {
            try await container.serverService.setPlaylistKindHidden(
                serverId: serverId, kind: kind, isHidden: isHidden
            )
        } catch {
            Logger.playlist.error("[PLAYLIST] could not change the type filter: \(error, privacy: .public)")
            container.toastService.showError(String(localized: "Couldn't change the filter. Please try again."))
        }
    }
}
