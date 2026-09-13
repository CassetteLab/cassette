// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Shared warning before queueing a large batch of downloads — identical in the Songs and
    /// Favorites lists, the same way `deletePlaylistConfirmation` is shared across the playlist
    /// views. It is a speed bump, not a block: Continue queues the batch unchanged.
    ///
    /// Callers only present this above `BulkDownload.confirmationThreshold`; a small batch starts
    /// straight away rather than paying for friction it doesn't need.
    ///
    /// `trackCount` is what is left to fetch — not the size of the list — so the number the user
    /// reads is the number of files that will actually be downloaded.
    func bulkDownloadConfirmation(
        trackCount: Int,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Download \(trackCount) tracks?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Continue") { onConfirm() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This downloads \(trackCount) tracks to this device. Keep Cassette open until it finishes.")
        }
    }
}
