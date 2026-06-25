// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Shared destructive-confirmation for deleting a playlist — identical across the playlist list and the
    /// iOS / macOS detail views (data-safety: same affordance everywhere).
    ///
    /// When the playlist has downloaded files (`hasDownloads`), it offers a CHOICE — keep the local files or
    /// purge them too — mirroring the per-song "Remove from Playlist" / "Remove Download" split. Otherwise it's
    /// a plain confirm. `onConfirm` receives `purgeDownloads`: `false` = server delete only, keep the local
    /// files (an intentional offline orphan); `true` = server delete + purge the downloads.
    func deletePlaylistConfirmation(
        playlistName: String,
        isPresented: Binding<Bool>,
        hasDownloads: Bool,
        onConfirm: @escaping (_ purgeDownloads: Bool) -> Void
    ) -> some View {
        confirmationDialog(
            "Delete \"\(playlistName)\"?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            if hasDownloads {
                Button("Delete Playlist Only", role: .destructive) { onConfirm(false) }
                Button("Delete Playlist & Downloads", role: .destructive) { onConfirm(true) }
            } else {
                Button("Delete", role: .destructive) { onConfirm(false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(hasDownloads
                ? "This removes the playlist from your server. You can keep the files downloaded on this device, or remove them too. This cannot be undone."
                : "This permanently deletes the playlist from your server. This action cannot be undone.")
        }
    }
}
