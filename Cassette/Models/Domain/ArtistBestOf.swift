// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// A virtual "best of" playlist: every song the user has starred for one artist, gathered across albums.
///
/// Derived from `getStarred2` on demand instead of materialised as a server playlist. That keeps it in sync
/// with the stars it's built from by construction, and spares the user's library one playlist per artist they
/// ever liked a track from. The trade-off is that it exists only inside Cassette — other clients don't see it.
nonisolated struct ArtistBestOf: Identifiable, Hashable, Sendable {
    /// Minimum liked tracks before an artist earns a best-of. Under it the artist screen lists the tracks
    /// inline instead — "The best of X" over two songs reads like a bug, not a playlist.
    static let minimumSongs = 5

    let artistId: String
    let artistName: String
    let coverArtId: String?
    let songs: [DisplayableSong]

    var id: String { artistId }
}

extension ArtistBestOf {
    /// Every artist the user has starred enough songs from, richest best-of first.
    ///
    /// Songs the server returns without an `artistId` are skipped: grouping those by name alone would merge
    /// distinct artists that happen to share one. A single artist's screen doesn't have that problem — it
    /// already knows which artist it's asking about — so it uses `songs(of:named:in:)`, which can afford a
    /// name fallback.
    static func all(in starred: [Song]) -> [ArtistBestOf] {
        Dictionary(grouping: starred.filter { $0.artistId != nil }, by: { $0.artistId! })
            .compactMap { artistId, songs -> ArtistBestOf? in
                guard songs.count >= minimumSongs else { return nil }
                let ordered = songs.mostRecentlyStarredFirst
                return ArtistBestOf(
                    artistId: artistId,
                    artistName: ordered.first?.artist ?? "",
                    coverArtId: ordered.first?.coverArt,
                    songs: ordered.map { DisplayableSong(from: $0) }
                )
            }
            .sorted {
                $0.songs.count == $1.songs.count
                    ? $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending
                    : $0.songs.count > $1.songs.count
            }
    }

    /// The starred songs of one known artist, most recently liked first.
    static func songs(of artistId: String, named artistName: String?, in starred: [Song]) -> [DisplayableSong] {
        starred
            .filter { matches($0, artistId: artistId, artistName: artistName) }
            .mostRecentlyStarredFirst
            .map { DisplayableSong(from: $0) }
    }

    /// Matches every id the server might carry (track artist, OpenSubsonic contributors, album artists),
    /// falling back to a name compare only when the track has no artist id at all — some servers drop it
    /// from the starred payload.
    static func matches(_ song: Song, artistId: String, artistName: String?) -> Bool {
        if song.artistId == artistId { return true }
        if song.artists?.contains(where: { $0.id == artistId }) == true { return true }
        if song.albumArtists?.contains(where: { $0.id == artistId }) == true { return true }
        guard song.artistId == nil, let artistName, let songArtist = song.artist else { return false }
        return songArtist.localizedCaseInsensitiveCompare(artistName) == .orderedSame
    }

    /// Filters a fetched list through the local star cache so unstarring a track drops it from the view
    /// immediately, with no refetch. That cache mirrors the server (synced at launch, written optimistically
    /// on star/unstar); before the first sync lands it is empty, so trust the fetched list rather than
    /// hiding everything.
    static func filteredByLocalStars(_ songs: [DisplayableSong], starredSongIds: Set<String>) -> [DisplayableSong] {
        guard !starredSongIds.isEmpty else { return songs }
        return songs.filter { starredSongIds.contains($0.id) }
    }
}

private extension Array where Element == Song {
    /// Most recently starred first; tracks whose server omitted the date sink to the bottom.
    var mostRecentlyStarredFirst: [Song] {
        sorted { ($0.starred ?? .distantPast) > ($1.starred ?? .distantPast) }
    }
}
