// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// A track described by its metadata rather than by an id.
nonisolated struct TrackDescriptor: Sendable, Equatable, Hashable {
    let title: String
    let artist: String?
    let album: String?

    init(title: String, artist: String? = nil, album: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
    }

    /// Stable key for caching a resolution across moods, since a track routinely appears in more
    /// than one.
    var cacheKey: String {
        "\(TrackMatcher.normalise(title))|\(TrackMatcher.normalise(artist ?? ""))"
    }
}

/// Picks the library track a piece of foreign metadata refers to.
///
/// Needed because AudioMuse can answer with its own internal ids, which the music server does not
/// recognise. Its results still carry title, artist and album, so the track can be found by
/// searching for it instead — the choice of tracks stays AudioMuse's, only its identifiers are
/// discarded.
///
/// Deliberately conservative: a wrong track in a playlist is worse than a missing one, so anything
/// short of a confident match returns nil.
nonisolated enum TrackMatcher {

    /// Folds text to comparable letters. Shared with the tag matcher so "Hip-Hop/Rap" and
    /// "hip hop" agree here too.
    static func normalise(_ text: String) -> String { MoodTagMatcher.normalise(text) }

    /// The candidate that best matches `wanted`, or nil when none is convincing.
    ///
    /// The artist is the deciding signal. Titles collide constantly across a library — live
    /// versions, covers, remasters, "Intro" on every second album — so a title-only match is
    /// refused whenever the wanted track names an artist. Without an artist to check against, an
    /// unambiguous title match is accepted and an ambiguous one is not.
    static func bestMatch(for wanted: TrackDescriptor, among candidates: [TrackDescriptor.Candidate]) -> String? {
        let wantedTitle = normalise(wanted.title)
        guard !wantedTitle.isEmpty else { return nil }

        let titleMatches = candidates.filter { candidate in
            let title = normalise(candidate.title)
            guard !title.isEmpty else { return false }
            // Containment either way absorbs the suffixes servers and taggers add or drop:
            // "Song (Remastered)" against "Song", "Song - Live" against "Song".
            return title == wantedTitle || title.contains(wantedTitle) || wantedTitle.contains(title)
        }
        guard !titleMatches.isEmpty else { return nil }

        guard let wantedArtist = wanted.artist.map(normalise), !wantedArtist.isEmpty else {
            // No artist to disambiguate with: accept only when the title picks out one track.
            return titleMatches.count == 1 ? titleMatches[0].id : nil
        }

        let artistMatches = titleMatches.filter { candidate in
            let artist = normalise(candidate.artist ?? "")
            guard !artist.isEmpty else { return false }
            return artist == wantedArtist || artist.contains(wantedArtist) || wantedArtist.contains(artist)
        }
        // A title that matched under the wrong artist is not this track. Falling back to it would
        // quietly fill the playlist with covers and namesakes.
        guard !artistMatches.isEmpty else { return nil }

        // Prefer an exact title, then an exact artist, then the smallest id — so the same library
        // always resolves to the same track and the playlist does not reshuffle between runs.
        let ranked = artistMatches.sorted { lhs, rhs in
            let lhsExactTitle = normalise(lhs.title) == wantedTitle
            let rhsExactTitle = normalise(rhs.title) == wantedTitle
            if lhsExactTitle != rhsExactTitle { return lhsExactTitle }
            let lhsExactArtist = normalise(lhs.artist ?? "") == wantedArtist
            let rhsExactArtist = normalise(rhs.artist ?? "") == wantedArtist
            if lhsExactArtist != rhsExactArtist { return lhsExactArtist }
            return lhs.id < rhs.id
        }
        return ranked.first?.id
    }
}

extension TrackDescriptor {
    /// A library track offered as a possible match.
    nonisolated struct Candidate: Sendable, Equatable {
        let id: String
        let title: String
        let artist: String?

        init(id: String, title: String, artist: String? = nil) {
            self.id = id
            self.title = title
            self.artist = artist
        }
    }
}
