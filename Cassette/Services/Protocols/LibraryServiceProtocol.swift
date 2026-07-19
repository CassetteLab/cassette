// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// A seed for an AudioMuse-AI Instant Mix. The case decides which Subsonic similarity endpoint is used:
/// song/album seeds go through the folder-based `getSimilarSongs`, an artist seed through the ID3-based
/// `getSimilarSongs2`. ("Radio" is deliberately avoided — it means Internet radio stations elsewhere.)
nonisolated enum InstantMixSeed: Sendable, Hashable {
    case song(id: String)
    case album(id: String)
    case artist(id: String)
}

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

    /// One page of the library's songs via search3's empty-query wildcard — Navidrome's only whole-library
    /// song enumeration (there is no dedicated endpoint). Returned in server order; callers page with
    /// `offset`/`count` and sort client-side once loaded.
    func allSongs(offset: Int, count: Int) async throws -> [Song]

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

    /// Raw `getSongsByGenre`, returning `Song` rather than `DisplayableSong` so callers keep the
    /// OpenSubsonic `moods` and `bpm` tags — which is the whole point for the tag-based mood
    /// fallback. Returns an empty array when the server has nothing under that genre.
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song]

    /// Builds a queue of tracks for Smart Shuffle ("Rediscover Your Library").
    ///
    /// Online: TRULY random — `getRandomSongs(targetSize)`, no recency weighting,
    /// no `played` filtering (product rule since the queue-modes rework).
    ///
    /// Offline: returns a pure shuffle over downloaded tracks for the active server.
    ///
    /// May return fewer than `targetSize` tracks or an empty array if the library is too small.
    /// Throws only on network/auth failures in the online path.
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong]

    /// Builds the queue auto-extend backfill: tracks SIMILAR to the last 20 played
    /// (≥30s listens), via an artist/genre heuristic that works on any self-hosted
    /// server — artist discographies (getArtist→albums) + getSongsByGenre, never
    /// popularity-backed endpoints.
    ///
    /// `excludedIds` (current queue) and the recent-20 track ids are never returned.
    /// Degrades to pure random with no listening history or a thin pool; offline
    /// falls back to downloaded tracks only.
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong]

    // TODO(v1.x): verify Navidrome savePlayQueue / getPlayQueue support before relying on these
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws
    func getPlayQueue() async throws -> SavedPlayQueue?

    // MARK: - Similar artists support

    /// Returns raw `ArtistInfo` for the given Subsonic artist ID.
    /// Results are cached in-memory for the lifetime of the active server connection.
    /// A 15-second timeout guards against slow external lookups (Last.fm/MusicBrainz)
    /// that some Subsonic server implementations trigger on `getArtistInfo`.
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo

    /// Returns the MusicBrainz ID for the given Subsonic artist ID.
    /// Delegates to `getArtistInfo(forArtistID:count:)` and extracts `musicBrainzId`.
    func getArtistMBID(forArtistID artistID: String) async throws -> String?

    /// Returns the first library artist whose name matches case-insensitively.
    /// Uses a lazy in-memory index built on first call; subsequent lookups are O(1).
    func findArtist(byName name: String) async -> ArtistID3?

    /// The artist's top (most-played) songs via Subsonic `getTopSongs` (popularity/Last.fm-backed — may be
    /// empty on bare self-hosted servers, in which case callers hide the section).
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong]

    /// Builds an Instant Mix from a seed via the Subsonic similarity endpoints (AudioMuse-AI plugin).
    /// Returns an empty array when the server has no similarity data — callers surface `instantMixEmpty`.
    /// Not gated on a capability: it simply calls the endpoint and lets an empty/failed result degrade.
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong]
}
