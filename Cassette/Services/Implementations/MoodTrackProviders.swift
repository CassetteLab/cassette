// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import SwiftMuse
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

/// A failure specific to how Cassette turns AudioMuse results into playlist ids, distinct from the
/// transport and HTTP failures ``SwiftMuseError`` reports from the client itself.
nonisolated enum MoodProviderError: Error, Equatable, Sendable {
    /// AudioMuse answered only with internal canonical (`fp_`) ids AND none of them could be
    /// recovered by name from the library. Distinct from an empty result: there were tracks, just
    /// none the music server can play.
    case internalIdsOnly
}

/// Maps a ``SonicTrack`` to the metadata used to find it in the library when AudioMuse handed back
/// an id the music server cannot match. Kept in the app rather than on the package's model, so the
/// client stays free of Cassette types.
extension SonicTrack {
    nonisolated var descriptor: TrackDescriptor? {
        guard let title, !title.isEmpty else { return nil }
        return TrackDescriptor(title: title, artist: author, album: album)
    }
}

/// Sonic search. The good one.
///
/// AudioMuse can answer with ids the music server does not recognise — its internal canonical ones,
/// when its own track mapping is incomplete. Those are recovered rather than discarded: the results
/// carry title and artist, so the track is looked up in the library instead. What AudioMuse is good
/// at, choosing the tracks, is kept; what it got wrong, naming them, is redone here.
nonisolated struct AudioMuseTrackProvider: MoodTrackProvider {
    let client: SwiftMuseClient
    /// Resolves tracks by metadata. Absent in tests that only exercise the id path.
    let resolver: SubsonicTrackResolver?

    init(client: SwiftMuseClient, resolver: SubsonicTrackResolver? = nil) {
        self.client = client
        self.resolver = resolver
    }

    var kind: MoodSourceKind { .sonic }

    /// Loads the CLAP model up front — it is evicted after ten minutes idle, so a weekly job always
    /// arrives cold and would otherwise pay the load inside the first mood's timeout.
    func prepare() async { await client.warmup() }

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        let results = try await client.search(query: mood.query, limit: limit)
        guard !results.isEmpty else { return [] }

        // Usable ids keep their position; the rest are looked up by name. Order is preserved
        // because it is AudioMuse's similarity ranking — the best matches come first.
        var ids: [String] = []
        var unresolvable = 0
        var recovered = 0
        for track in results {
            if !track.hasInternalID {
                ids.append(track.itemID)
            } else if let resolver, let descriptor = track.descriptor, let id = await resolver.resolve(descriptor) {
                ids.append(id)
                recovered += 1
            } else {
                unresolvable += 1
            }
        }

        Logger.moodPlaylists.info("[MOOD-SONIC] \(mood.rawValue, privacy: .public): \(results.count, privacy: .public) results → \(ids.count, privacy: .public) usable (\(recovered, privacy: .public) recovered by name, \(unresolvable, privacy: .public) lost)")

        // Everything came back with an unusable id and nothing could be found in the library: the
        // caller must not treat that as a successful, empty playlist.
        if ids.isEmpty && !results.isEmpty { throw MoodProviderError.internalIdsOnly }
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
