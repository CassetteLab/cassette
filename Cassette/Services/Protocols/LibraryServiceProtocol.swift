// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

protocol LibraryServiceProtocol: AnyObject, Sendable {
    func artists() async throws -> [ArtistIndex]
    func artist(id: String) async throws -> ArtistID3
    func album(id: String) async throws -> AlbumID3

    /// Fetches every track from every album of the given artist.
    /// Albums are ordered most-recent first (by year); albums without a year come last (alphabetical).
    /// Uses a TaskGroup bounded to 5 concurrent album fetches — safe for home-server instances.
    /// Individual album failures are logged and skipped (best-effort). Throws `CassetteError.artistTracksUnavailable`
    /// only when every album fetch fails.
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong]
    func playlists() async throws -> [Playlist]
    func playlist(id: String) async throws -> PlaylistWithSongs
    func search(_ query: String) async throws -> SearchResult3
    func coverArtURL(id: String, size: Int?) async -> URL?
    func streamURL(songId: String) async -> URL?

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws
    func getStarred2() async throws -> Starred2
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3]
    func allAlbums() async throws -> [AlbumID3]

    // MARK: - Discover

    /// Notifies the server about playback activity. v1.3 uses both modes :
    /// - `submission: false` → "now playing" notification, sent at track start
    /// - `submission: true` → "completed play", sent after 30s of playback
    ///
    /// Errors are silenced — scrobble failures must not interrupt playback or surface to the user.
    /// Network/auth errors are logged at debug level.
    func scrobble(songId: String, submission: Bool) async

    /// Recently played albums (Subsonic `getAlbumList2?type=recent`).
    /// Granularity is album-level — Subsonic does not expose track-level history endpoints.
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3]

    /// Most played albums (Subsonic `getAlbumList2?type=frequent`).
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3]

    /// Random songs from the user's library. Used as the source pool for Smart Shuffle (phase 3).
    /// Server has no "exclude recently played" filter — filtering is done client-side by the consumer.
    func randomSongs(size: Int) async throws -> [Song]

    /// Builds a queue of tracks for Smart Shuffle (v1.3 Discover feature).
    ///
    /// Online: fetches a 200-song random pool, filters out tracks played in the last 30 days,
    /// relaxing to 60 then 90 days if the pool is too small, falling back to oldest-played
    /// first if the entire pool is recent. Returns up to `targetSize` tracks.
    ///
    /// Offline: returns a pure shuffle over downloaded tracks for the active server.
    /// No play-date filtering — DownloadedTrack has no local play-date field (roadmap item).
    ///
    /// May return fewer than `targetSize` tracks or an empty array if the library is too small.
    /// Throws only on network/auth failures in the online path.
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong]

    // TODO(v1.x): verify Navidrome savePlayQueue / getPlayQueue support before relying on these
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws
    func getPlayQueue() async throws -> SavedPlayQueue?

    // MARK: - Similar artists support

    /// Returns the MusicBrainz ID for the given Subsonic artist ID by calling `getArtistInfo2`.
    /// Returns `nil` when the server does not supply MBID data (e.g. non-OpenSubsonic servers).
    func getArtistMBID(forArtistID artistID: String) async throws -> String?

    /// Returns the first library artist whose name matches case-insensitively.
    /// Uses a lazy in-memory index built on first call; subsequent lookups are O(1).
    func findArtist(byName name: String) async -> ArtistID3?
}
