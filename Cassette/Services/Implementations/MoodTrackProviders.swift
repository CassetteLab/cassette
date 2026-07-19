// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

// MARK: - MoodTrackProvider

/// Where a mood's tracks come from. Two implementations, in descending order of quality:
/// AudioMuse's sonic analysis, and the server's own tags.
nonisolated protocol MoodTrackProvider: Sendable {
    /// How the source describes itself in the UI.
    var kind: MoodSourceKind { get }
    /// One-off setup before a batch of moods. Free to be a no-op.
    func prepare() async
    /// Track ids for a mood, best match first. Empty means "no confident answer" — never a reason
    /// to overwrite an existing playlist.
    func trackIds(for mood: Mood, limit: Int) async throws -> [String]
}

nonisolated enum MoodSourceKind: String, Sendable, Equatable {
    /// AudioMuse-AI: matches on how the audio actually sounds.
    case sonic
    /// The server's MOOD, genre and BPM tags: matches on what somebody wrote in the files.
    case tags
}

// MARK: - AudioMuse

/// Sonic search. The good one.
nonisolated struct AudioMuseTrackProvider: MoodTrackProvider {
    let client: AudioMuseClient

    var kind: MoodSourceKind { .sonic }

    /// Loads the CLAP model up front — it is evicted after ten minutes idle, so a weekly job always
    /// arrives cold and would otherwise pay the load inside the first mood's timeout.
    func prepare() async { await client.warmup() }

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        try await client.search(query: mood.query, limit: limit).map(\.itemId)
    }
}

// MARK: - Tags

/// Fallback for servers with no AudioMuse instance: rank the library's own tags.
///
/// Genuinely weaker than sonic analysis and does not pretend otherwise — see MoodTagMatcher. What
/// it does have is universality: `getSongsByGenre`, `moods` and `bpm` are plain OpenSubsonic, so
/// this works against any server, with nothing to install.
///
/// Candidates are gathered per mood by querying that mood's genres rather than by scanning the
/// library, which keeps the cost to a handful of indexed server queries instead of a full walk.
nonisolated struct LibraryTagTrackProvider: MoodTrackProvider {
    let libraryService: any LibraryServiceProtocol

    /// Fetched per genre. Generous, because ranking then cuts it back hard — a wide net matters
    /// more than a cheap one here, and these are indexed lookups.
    static let perGenreFetch = 200

    var kind: MoodSourceKind { .tags }

    func prepare() async {}

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        var seen = Set<String>()
        var candidates: [(id: String, features: SongTagFeatures)] = []

        for genre in MoodTagMatcher.genres(mood) {
            // A genre the library simply does not have is normal, not an error — skip and continue,
            // otherwise one absent genre would sink the whole mood.
            guard let songs = try? await libraryService.songsByGenre(genre, count: Self.perGenreFetch) else { continue }
            for song in songs where seen.insert(song.id).inserted {
                candidates.append((song.id, Self.features(of: song)))
            }
        }

        let ranked = MoodTagMatcher.rank(candidates, for: mood, limit: limit)
        Logger.moodPlaylists.info("[MOOD-TAGS] \(mood.rawValue, privacy: .public): \(candidates.count, privacy: .public) candidates → \(ranked.count, privacy: .public) ranked")
        return ranked
    }

    /// Reads both genre spellings: OpenSubsonic's `genres` array and the older single `genre`
    /// string, since servers populate one, the other, or both.
    static func features(of song: Song) -> SongTagFeatures {
        var genres = song.genres?.map(\.name) ?? []
        if let legacy = song.genre, !genres.contains(legacy) { genres.append(legacy) }
        return SongTagFeatures(moods: song.moods ?? [], genres: genres, bpm: song.bpm)
    }
}
