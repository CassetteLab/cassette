// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
    func deletePlaylist(id: String) async throws
}
