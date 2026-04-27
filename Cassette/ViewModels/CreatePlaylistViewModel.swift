// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

@MainActor
@Observable
final class CreatePlaylistViewModel {
    var name: String = ""
    var description: String = ""
    private(set) var isCreating: Bool = false

    private let playlistService: any PlaylistServiceProtocol
    private let toastService: ToastService

    init(playlistService: any PlaylistServiceProtocol, toastService: ToastService) {
        self.playlistService = playlistService
        self.toastService = toastService
    }

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    func create() async -> PlaylistWithSongs? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        isCreating = true
        defer { isCreating = false }

        do {
            let playlist = try await playlistService.createPlaylist(
                name: trimmedName,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc
            )
            toastService.showSuccess("Playlist created")
            return playlist
        } catch {
            Logger.playlist.error("Failed to create playlist: \(error)")
            toastService.showError("Failed to create playlist. Try again.")
            return nil
        }
    }
}
