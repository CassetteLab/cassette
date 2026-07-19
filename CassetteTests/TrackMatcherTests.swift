// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("Track matching by metadata")
struct TrackMatcherTests {

    private func candidate(_ id: String, _ title: String, _ artist: String? = nil) -> TrackDescriptor.Candidate {
        TrackDescriptor.Candidate(id: id, title: title, artist: artist)
    }

    @Test("an exact title and artist resolves")
    func exactMatch() {
        let wanted = TrackDescriptor(title: "Tenere", artist: "Tinariwen")
        let match = TrackMatcher.bestMatch(for: wanted, among: [
            candidate("a", "Something Else", "Tinariwen"),
            candidate("b", "Tenere", "Tinariwen"),
        ])
        #expect(match == "b")
    }

    @Test("a title matching under the wrong artist is refused")
    func wrongArtistIsRefused() {
        // The failure that matters: every library has a dozen tracks sharing a title, and picking
        // one at random fills the playlist with covers and namesakes.
        let wanted = TrackDescriptor(title: "Intro", artist: "Orelsan")
        let match = TrackMatcher.bestMatch(for: wanted, among: [
            candidate("a", "Intro", "Nekfeu"),
            candidate("b", "Intro", "Disiz"),
        ])
        #expect(match == nil)
    }

    @Test("suffixes on either side still match")
    func suffixesAreTolerated() {
        let wanted = TrackDescriptor(title: "Basique", artist: "Orelsan")
        #expect(TrackMatcher.bestMatch(for: wanted, among: [candidate("a", "Basique (Remastered)", "Orelsan")]) == "a")

        let wantedLong = TrackDescriptor(title: "Basique - Live", artist: "Orelsan")
        #expect(TrackMatcher.bestMatch(for: wantedLong, among: [candidate("a", "Basique", "Orelsan")]) == "a")
    }

    @Test("punctuation and case differences do not prevent a match")
    func normalisationApplies() {
        let wanted = TrackDescriptor(title: "L'odeur de l'essence", artist: "Orelsan")
        #expect(TrackMatcher.bestMatch(for: wanted, among: [candidate("a", "L’odeur de l'Essence", "ORELSAN")]) == "a")
    }

    @Test("an exact title wins over a merely containing one")
    func exactTitlePreferred() {
        let wanted = TrackDescriptor(title: "Suicide Social", artist: "Orelsan")
        let match = TrackMatcher.bestMatch(for: wanted, among: [
            candidate("a", "Suicide Social (Instrumental)", "Orelsan"),
            candidate("b", "Suicide Social", "Orelsan"),
        ])
        #expect(match == "b")
    }

    @Test("with no artist, an ambiguous title is refused and a unique one accepted")
    func artistlessMatching() {
        let wanted = TrackDescriptor(title: "Intro", artist: nil)
        #expect(TrackMatcher.bestMatch(for: wanted, among: [
            candidate("a", "Intro", "X"), candidate("b", "Intro", "Y"),
        ]) == nil)
        #expect(TrackMatcher.bestMatch(for: wanted, among: [candidate("a", "Intro", "X")]) == "a")
    }

    @Test("no candidates, or none matching, resolves to nothing")
    func noMatch() {
        let wanted = TrackDescriptor(title: "Tenere", artist: "Tinariwen")
        #expect(TrackMatcher.bestMatch(for: wanted, among: []) == nil)
        #expect(TrackMatcher.bestMatch(for: wanted, among: [candidate("a", "Completely Other", "Someone")]) == nil)
    }

    @Test("an empty title never matches anything")
    func emptyTitleIsRejected() {
        #expect(TrackMatcher.bestMatch(for: TrackDescriptor(title: "", artist: "X"),
                                       among: [candidate("a", "Anything", "X")]) == nil)
    }

    @Test("equal candidates break on id, so the playlist is stable between runs")
    func tiesAreStable() {
        let wanted = TrackDescriptor(title: "Tenere", artist: "Tinariwen")
        let a = candidate("aaa", "Tenere", "Tinariwen")
        let b = candidate("bbb", "Tenere", "Tinariwen")
        #expect(TrackMatcher.bestMatch(for: wanted, among: [b, a]) == "aaa")
        #expect(TrackMatcher.bestMatch(for: wanted, among: [a, b]) == "aaa")
    }

    @Test("the cache key ignores formatting differences")
    func cacheKeyIsNormalised() {
        let a = TrackDescriptor(title: "L'Odeur", artist: "Orelsan")
        let b = TrackDescriptor(title: "l odeur", artist: "ORELSAN")
        #expect(a.cacheKey == b.cacheKey)
    }
}
