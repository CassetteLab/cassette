// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("Mood playlists — tag-based fallback scoring")
struct MoodTagMatcherTests {

    // MARK: - Absence of signal

    @Test("a track with no tags at all scores nil, not zero")
    func noTagsMeansNoOpinion() {
        // The distinction matters: nil drops the track, zero would rank it. A library with no tags
        // must produce an empty result rather than an arbitrary one.
        #expect(MoodTagMatcher.score(SongTagFeatures(), for: .chill) == nil)
    }

    @Test("a BPM of zero is treated as missing, not as a very slow track")
    func zeroBpmIsMissing() {
        // Servers write 0 for "unknown" — taking it literally would file everything under Night.
        #expect(MoodTagMatcher.score(SongTagFeatures(bpm: 0), for: .night) == nil)
    }

    @Test("a tagged track that matches nothing scores zero, which is an opinion")
    func taggedButUnmatchedScoresZero() {
        let polka = SongTagFeatures(genres: ["Polka"], bpm: 115)
        #expect(MoodTagMatcher.score(polka, for: .night) == 0)
    }

    // MARK: - Weighting

    @Test("a MOOD tag counts for more than a genre")
    func moodTagOutweighsGenre() {
        let byMood = SongTagFeatures(moods: ["Relaxed"])
        let byGenre = SongTagFeatures(genres: ["Soul"])
        let moodScore = MoodTagMatcher.score(byMood, for: .chill)
        let genreScore = MoodTagMatcher.score(byGenre, for: .chill)
        #expect(moodScore != nil && genreScore != nil)
        #expect(moodScore! > genreScore!)
    }

    @Test("signals accumulate, so a track matching all three wins")
    func signalsStack() {
        let everything = SongTagFeatures(moods: ["energetic"], genres: ["Dance"], bpm: 140)
        let onlyGenre = SongTagFeatures(genres: ["Dance"])
        #expect(MoodTagMatcher.score(everything, for: .energetic)! > MoodTagMatcher.score(onlyGenre, for: .energetic)!)
    }

    // MARK: - Matching behaviour

    @Test("MOOD tags match on substrings, since they are free text")
    func moodTagsMatchLoosely() {
        // "Relaxing", "relaxed", "Calm/Relaxed" all have to hit the same keyword.
        for tag in ["Relaxing", "relaxed", "Calm/Relaxed"] {
            let features = SongTagFeatures(moods: [tag])
            #expect(MoodTagMatcher.score(features, for: .chill)! >= MoodTagMatcher.moodTagWeight,
                    "\(tag) should match chill")
        }
    }

    @Test("compound genres still match their root")
    func compoundGenresMatch() {
        let hipHop = SongTagFeatures(genres: ["Hip-Hop/Rap"])
        #expect(MoodTagMatcher.score(hipHop, for: .workout)! >= MoodTagMatcher.genreWeight)
    }

    @Test("BPM only counts for the moods where tempo means something")
    func bpmIsIgnoredForFocus() {
        // Focus spans a slow piano piece and a steady techno loop equally well.
        #expect(MoodTagMatcher.bpmRange(.focus) == nil)
        let fast = SongTagFeatures(bpm: 170)
        let slow = SongTagFeatures(bpm: 60)
        #expect(MoodTagMatcher.score(fast, for: .focus) == MoodTagMatcher.score(slow, for: .focus))
    }

    @Test("tempo separates energetic from night")
    func tempoSeparatesOppositeMoods() {
        let fast = SongTagFeatures(bpm: 150)
        let slow = SongTagFeatures(bpm: 65)
        #expect(MoodTagMatcher.score(fast, for: .energetic)! > MoodTagMatcher.score(fast, for: .night)!)
        #expect(MoodTagMatcher.score(slow, for: .night)! > MoodTagMatcher.score(slow, for: .energetic)!)
    }

    // MARK: - Ranking

    @Test("ranking drops tracks that matched nothing")
    func rankingDropsZeroScores() {
        let candidates: [(id: String, features: SongTagFeatures)] = [
            ("good", SongTagFeatures(moods: ["calm"], genres: ["Ambient"], bpm: 70)),
            ("bad", SongTagFeatures(genres: ["Speed Metal"], bpm: 200)),
        ]
        #expect(MoodTagMatcher.rank(candidates, for: .night, limit: 10) == ["good"])
    }

    @Test("ranking drops untagged tracks entirely")
    func rankingDropsUntagged() {
        let candidates: [(id: String, features: SongTagFeatures)] = [
            ("tagged", SongTagFeatures(genres: ["Ambient"])),
            ("untagged", SongTagFeatures()),
        ]
        #expect(MoodTagMatcher.rank(candidates, for: .night, limit: 10) == ["tagged"])
    }

    @Test("ranking honours the limit, keeping the best")
    func rankingHonoursLimit() {
        let candidates: [(id: String, features: SongTagFeatures)] = [
            ("weak", SongTagFeatures(genres: ["Ambient"])),
            ("strong", SongTagFeatures(moods: ["calm"], genres: ["Ambient"], bpm: 70)),
            ("medium", SongTagFeatures(genres: ["Ambient"], bpm: 70)),
        ]
        #expect(MoodTagMatcher.rank(candidates, for: .night, limit: 2) == ["strong", "medium"])
    }

    @Test("equal scores break on id, so the playlist is stable between runs")
    func tiesAreStable() {
        let a = ("aaa", SongTagFeatures(genres: ["Ambient"]))
        let b = ("bbb", SongTagFeatures(genres: ["Ambient"]))
        #expect(MoodTagMatcher.rank([b, a], for: .night, limit: 2) == ["aaa", "bbb"])
        #expect(MoodTagMatcher.rank([a, b], for: .night, limit: 2) == ["aaa", "bbb"])
    }

    @Test("every mood defines keywords and genres to look for")
    func everyMoodIsFullyDefined() {
        for mood in Mood.allCases {
            #expect(!MoodTagMatcher.moodKeywords(mood).isEmpty, "\(mood.rawValue) has no mood keywords")
            #expect(!MoodTagMatcher.genres(mood).isEmpty, "\(mood.rawValue) has no genres to query")
        }
    }
}
