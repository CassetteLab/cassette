// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftUI
import SwiftSonic
import OSLog

@MainActor
@Observable
final class EditPlaylistViewModel {
    var name: String
    var description: String

    private(set) var songs: [Song] = []
    private(set) var isSavingForm = false
    private(set) var isDeletingPlaylist = false

    private let originalName: String
    private let originalDescription: String
    let playlistId: String

    private let playlistService: any PlaylistServiceProtocol
    private let toastService: ToastService

    init(
        playlist: PlaylistWithSongs,
        playlistService: any PlaylistServiceProtocol,
        toastService: ToastService
    ) {
        self.playlistId = playlist.id
        self.name = playlist.name
        self.originalName = playlist.name
        self.description = playlist.comment ?? ""
        self.originalDescription = playlist.comment ?? ""
        self.songs = playlist.entry ?? []
        self.playlistService = playlistService
        self.toastService = toastService
    }

    var hasFormChanges: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != originalName ||
        description.trimmingCharacters(in: .whitespacesAndNewlines) !=
            originalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSaveForm: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasFormChanges
            && !isSavingForm
    }

    // MARK: - Form save

    /// Persists name and description changes. Returns true on full success.
    func saveForm() async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        isSavingForm = true
        defer { isSavingForm = false }

        var success = true

        if trimmedName != originalName {
            do {
                try await playlistService.renamePlaylist(id: playlistId, newName: trimmedName)
            } catch {
                Logger.playlist.error("EditPlaylistViewModel: rename failed: \(error)")
                toastService.showError("Failed to rename playlist")
                success = false
            }
        }

        let originalTrimmedDesc = originalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDesc != originalTrimmedDesc && success {
            do {
                try await playlistService.updateDescription(id: playlistId, description: trimmedDesc)
            } catch {
                Logger.playlist.error("EditPlaylistViewModel: description update failed: \(error)")
                toastService.showError("Failed to update description")
                success = false
            }
        }

        if success {
            toastService.showSuccess("Playlist updated")
        }
        return success
    }

    // MARK: - Track mutations (optimistic, immediate)

    /// Removes the track at `index`. Rolls back on failure.
    func removeTrack(at index: Int) async {
        guard songs.indices.contains(index) else { return }
        let removed = songs[index]
        songs.remove(at: index)
        do {
            try await playlistService.removeTracks(playlistId: playlistId, indices: [index])
        } catch {
            songs.insert(removed, at: index)
            Logger.playlist.error("EditPlaylistViewModel: remove track failed: \(error)")
            toastService.showError("Failed to remove track")
        }
    }

    /// Reorders tracks using SwiftUI's move offsets. Rolls back on failure.
    func moveTracks(from source: IndexSet, to destination: Int) async {
        let originalSongs = songs
        songs.move(fromOffsets: source, toOffset: destination)
        let newOrder = songs.map(\.id)
        do {
            try await playlistService.reorderTracks(playlistId: playlistId, orderedSongIds: newOrder)
        } catch {
            songs = originalSongs
            Logger.playlist.error("EditPlaylistViewModel: reorder failed: \(error)")
            toastService.showError("Failed to reorder tracks")
        }
    }

    // MARK: - Delete playlist

    /// Deletes the entire playlist. Returns true on success.
    func deletePlaylist() async -> Bool {
        isDeletingPlaylist = true
        defer { isDeletingPlaylist = false }
        do {
            try await playlistService.deletePlaylist(id: playlistId)
            toastService.showSuccess("Playlist deleted")
            return true
        } catch {
            Logger.playlist.error("EditPlaylistViewModel: delete failed: \(error)")
            toastService.showError("Failed to delete playlist")
            return false
        }
    }
}
