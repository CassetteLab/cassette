// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// The tag signals a mood can be judged on, lifted out of `Song` so the scoring is testable
/// without constructing SwiftSonic models.
nonisolated struct SongTagFeatures: Sendable, Equatable {
    let moods: [String]
    let genres: [String]
    let bpm: Int?

    init(moods: [String] = [], genres: [String] = [], bpm: Int? = nil) {
        self.moods = moods
        self.genres = genres
        self.bpm = bpm
    }
}

/// Scores a track against a mood using only the tags the server already has.
///
/// This is the fallback for libraries with no AudioMuse instance. It is genuinely weaker: a MOOD
/// tag is somebody's opinion written into a file, a genre is a category, and BPM says nothing about
/// whether a fast track is joyful or bleak. AudioMuse listens to the audio; this reads labels. The
/// point is to be useful when the good option is absent, not to pretend to match it.
///
/// Signals are weighted by how much they actually say:
/// - a MOOD tag hit is worth most — it is the only tag that describes feel rather than category
/// - BPM sits in the middle, and only for the moods where tempo means something
/// - genre is the weakest, but it is the tag libraries actually have
nonisolated enum MoodTagMatcher {

    static let moodTagWeight = 3.0
    static let bpmWeight = 2.0
    static let genreWeight = 1.0

    /// Words looked for inside a track's MOOD tags. Substring matching, lowercased, because these
    /// tags are free text and arrive as "Calm", "calm/relaxed", "Relaxing" in equal measure.
    static func moodKeywords(_ mood: Mood) -> [String] {
        switch mood {
        case .night:     return ["calm", "ambient", "dreamy", "mellow", "sleep", "quiet", "soft", "atmospheric", "nocturnal"]
        case .energetic: return ["energetic", "happy", "upbeat", "party", "driving", "bright", "euphoric"]
        case .workout:   return ["aggressive", "energetic", "intense", "powerful", "driving", "angry"]
        case .chill:     return ["chill", "relax", "mellow", "laid", "smooth", "lazy", "warm"]
        case .focus:     return ["instrumental", "calm", "ambient", "minimal", "meditative", "hypnotic"]
        }
    }

    /// Genres queried on the server and matched against. Also substring-matched, so "Hip-Hop/Rap"
    /// catches "hip hop" and "Post-Rock" catches "rock" — deliberate, since genre is the loose
    /// signal anyway.
    static func genres(_ mood: Mood) -> [String] {
        switch mood {
        case .night:     return ["ambient", "downtempo", "chillout", "classical", "jazz"]
        case .energetic: return ["dance", "pop", "rock", "electronic", "punk"]
        case .workout:   return ["hip hop", "techno", "metal", "drum and bass", "house"]
        case .chill:     return ["lo-fi", "soul", "r&b", "reggae", "chillout"]
        case .focus:     return ["ambient", "classical", "instrumental", "soundtrack", "minimal"]
        }
    }

    /// Tempo window, or nil for moods where BPM carries no meaning. Focus is deliberately absent:
    /// concentration music spans a slow piano piece and a steady 140 BPM techno loop equally well,
    /// so tempo would only add noise.
    static func bpmRange(_ mood: Mood) -> ClosedRange<Int>? {
        switch mood {
        case .night:     return 40...100
        case .energetic: return 118...200
        case .workout:   return 128...200
        case .chill:     return 70...110
        case .focus:     return nil
        }
    }

    /// Folds a tag down to comparable letters so punctuation and joining words stop mattering.
    ///
    /// Tag spellings are wildly inconsistent across libraries: "Hip-Hop/Rap", "Hip Hop", "hiphop";
    /// "Drum & Bass" against "drum and bass"; "R&B" against "r&b". Splitting on non-alphanumerics,
    /// dropping a standalone "and", and rejoining makes all of those land on the same string.
    ///
    /// "and" is dropped as a whole token, never as a substring, so "Sandwich" survives intact.
    static func normalise(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0 != "and" }
            .joined()
    }

    private static func matches(_ tags: [String], anyOf keywords: [String]) -> Bool {
        let normalisedTags = tags.map(normalise)
        let normalisedKeywords = keywords.map(normalise)
        return normalisedTags.contains { tag in normalisedKeywords.contains { !$0.isEmpty && tag.contains($0) } }
    }

    /// Higher is a better match. `nil` means the track carried no usable signal at all — it is not
    /// a zero score, it is an absence of evidence, and such tracks are dropped rather than ranked
    /// last, so a library with no tags produces an empty result instead of an arbitrary one.
    static func score(_ features: SongTagFeatures, for mood: Mood) -> Double? {
        var total = 0.0
        var sawSignal = false

        if !features.moods.isEmpty {
            sawSignal = true
            if matches(features.moods, anyOf: moodKeywords(mood)) { total += moodTagWeight }
        }

        if !features.genres.isEmpty {
            sawSignal = true
            if matches(features.genres, anyOf: genres(mood)) { total += genreWeight }
        }

        if let bpm = features.bpm, bpm > 0, let range = bpmRange(mood) {
            sawSignal = true
            if range.contains(bpm) { total += bpmWeight }
        }

        guard sawSignal else { return nil }
        // A track that carried signals but matched none of them is a real "no", not an absence —
        // keep it scoreable at zero so ranking is well defined, and let the caller cut the tail.
        return total
    }

    /// Ranks candidates for a mood and keeps the best `limit`.
    ///
    /// Tracks scoring zero are dropped: they had tags and none of them fit, so including them would
    /// pad the playlist with music that matches nothing. Ties break on id to keep the output stable
    /// between runs — a playlist that reshuffles itself for no reason reads as broken.
    static func rank(_ candidates: [(id: String, features: SongTagFeatures)], for mood: Mood, limit: Int) -> [String] {
        candidates
            .compactMap { candidate -> (String, Double)? in
                guard let score = score(candidate.features, for: mood), score > 0 else { return nil }
                return (candidate.id, score)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
            .map(\.0)
    }
}
