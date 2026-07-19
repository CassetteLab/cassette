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
        let ids = try await client.search(query: mood.query, limit: limit).map(\.itemId)
        // The ids are logged because everything downstream depends on them being the MEDIA SERVER's
        // track ids and not AudioMuse's internal ones. A Subsonic server drops ids it does not know
        // and still answers 200, so a format mismatch looks exactly like success — the only way to
        // tell them apart is to read the ids and compare them with a known-good one.
        Logger.moodPlaylists.info("[MOOD-SONIC] \(mood.rawValue, privacy: .public): \(ids.count, privacy: .public) ids, first=\(ids.prefix(3).joined(separator: ","), privacy: .public)")
        return ids
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

    /// Broad sample taken when a mood's genres are absent from the library.
    static let fallbackPoolSize = 500

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        var candidates = await genreCandidates(for: mood)
        var source = "genres"

        // A library organised around genres this mood does not use — French rap where Night looks
        // for ambient and jazz — yields nothing at all here, and would keep yielding nothing every
        // week. Falling back to a broad sample lets the MOOD and BPM tags decide on their own,
        // which is exactly the case those two signals exist for.
        if candidates.isEmpty {
            candidates = await randomCandidates()
            source = "random pool"
        }

        let ranked = MoodTagMatcher.rank(candidates, for: mood, limit: limit)
        let withMoodTag = candidates.count { !$0.features.moods.isEmpty }
        let withBpm = candidates.count { ($0.features.bpm ?? 0) > 0 }
        // The signal breakdown is logged because an empty result is otherwise indistinguishable
        // between "no candidates" and "candidates with nothing to judge them on".
        Logger.moodPlaylists.info("[MOOD-TAGS] \(mood.rawValue, privacy: .public): \(candidates.count, privacy: .public) candidates via \(source, privacy: .public) (\(withMoodTag, privacy: .public) tagged, \(withBpm, privacy: .public) with BPM) → \(ranked.count, privacy: .public) ranked")
        return ranked
    }

    private func genreCandidates(for mood: Mood) async -> [(id: String, features: SongTagFeatures)] {
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
        return candidates
    }

    private func randomCandidates() async -> [(id: String, features: SongTagFeatures)] {
        guard let songs = try? await libraryService.randomSongs(size: Self.fallbackPoolSize) else { return [] }
        return songs.map { ($0.id, Self.features(of: $0)) }
    }

    /// Reads both genre spellings: OpenSubsonic's `genres` array and the older single `genre`
    /// string, since servers populate one, the other, or both.
    static func features(of song: Song) -> SongTagFeatures {
        var genres = song.genres?.map(\.name) ?? []
        if let legacy = song.genre, !genres.contains(legacy) { genres.append(legacy) }
        return SongTagFeatures(moods: song.moods ?? [], genres: genres, bpm: song.bpm)
    }
}
