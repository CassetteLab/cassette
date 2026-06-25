// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

protocol PlaylistServiceProtocol: AnyObject, Sendable {
    func listPlaylists() async throws -> [Playlist]
    func getPlaylist(id: String) async throws -> PlaylistWithSongs
    @discardableResult
    func createPlaylist(name: String, description: String?) async throws -> PlaylistWithSongs
    func renamePlaylist(id: String, newName: String) async throws
    func updateDescription(id: String, description: String) async throws
    func addTracks(playlistId: String, songs: [Song]) async throws
    func removeTracks(playlistId: String, indices: [Int]) async throws
    func reorderTracks(playlistId: String, orderedSongIds: [String]) async throws
    /// Deletes the playlist on the server. `purgeDownloads`: when true, also removes the downloaded files and the
    /// client-side cover choice for this playlist; when false, the server delete keeps any local downloads (an
    /// intentional offline orphan). Local state is only touched after a confirmed server delete.
    func deletePlaylist(id: String, purgeDownloads: Bool) async throws
}
