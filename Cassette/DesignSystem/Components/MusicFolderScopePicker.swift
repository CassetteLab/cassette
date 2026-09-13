// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftSonic
import SwiftUI

/// Scopes browsing to one of the server's libraries.
///
/// Renders nothing at all unless the server reports more than one library, which is the case for
/// almost every server: the point is to stay invisible for the people this does not concern.
/// The selection is persisted per server and survives a relaunch.
struct MusicFolderScopePicker: View {
    @Environment(\.appContainer) private var container
    @State private var folders: [MusicFolder] = []

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }
    private var selectedId: String? { activeServer?.selectedMusicFolderId }

    private var selectedName: String {
        guard let selectedId else { return String(localized: "All Libraries") }
        // A folder the server no longer reports falls back to the neutral label rather than
        // showing a stale name; the scope itself is left alone in case it comes back.
        return folders.first { $0.id == selectedId }?.name ?? String(localized: "All Libraries")
    }

    var body: some View {
        Group {
            if folders.count > 1 {
                Menu {
                    Picker("Library", selection: selectionBinding) {
                        Text("All Libraries").tag(String?.none)
                        ForEach(folders) { folder in
                            Text(folder.name ?? folder.id).tag(String?.some(folder.id))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(selectedName, systemImage: "square.stack.3d.up")
                        .font(.cassetteCaption)
                        .lineLimit(1)
                }
                .accessibilityLabel(Text("Library: \(selectedName)"))
            }
        }
        .task(id: activeServer?.id) { await loadFolders() }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { selectedId },
            set: { newValue in
                guard newValue != selectedId else { return }
                Task { await apply(newValue) }
            }
        )
    }

    private func loadFolders() async {
        guard let container, container.serverState.isOnline else { return }
        do {
            folders = try await container.libraryService.musicFolders()
        } catch {
            // A server that cannot answer simply gets no picker — never an error in the chrome.
            Logger.library.debug("Music folders unavailable: \(error, privacy: .public)")
            folders = []
        }
    }

    /// Persists the choice, then drops the library service's cached scope so the next request
    /// carries the new one. Playback is deliberately untouched: changing what you browse should
    /// not stop what you are listening to.
    private func apply(_ folderId: String?) async {
        guard let container, let serverId = activeServer?.id else { return }
        do {
            try await container.serverService.setMusicFolderScope(serverId: serverId, folderId: folderId)
            await container.libraryService.reloadMusicFolderScope()
        } catch {
            Logger.library.error("Could not change library scope: \(error, privacy: .public)")
            container.toastService.showError(String(localized: "Could not change library."))
        }
    }
}
