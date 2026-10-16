// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("ListenBrainzUsername")
struct ListenBrainzUsernameTests {

    @Test("a name with a dot is a real ListenBrainz account, and used to be refused")
    func dotsAreFine() {
        // The name from issue #111, verbatim.
        #expect(ListenBrainzUsername.isPlausible("Spartan_K.Kong"))
    }

    @Test("ordinary names pass")
    func ordinaryNames() {
        for name in ["alice", "Bob_42", "jean-luc", "a", "user.name.with.dots"] {
            #expect(ListenBrainzUsername.isPlausible(name), "\(name) should be accepted")
        }
    }

    @Test("names Cassette has no business judging are left to the server")
    func unusualButPossibleNames() {
        for name in ["Ünïcødé", "名前", "user+tag", "o'brien", "user@host"] {
            #expect(ListenBrainzUsername.isPlausible(name), "\(name) should be left to ListenBrainz")
        }
    }

    @Test("nothing to send is refused")
    func emptyIsRefused() {
        #expect(!ListenBrainzUsername.isPlausible(""))
    }

    @Test("a space or a newline is refused — never part of a name, usually a bad paste")
    func whitespaceIsRefused() {
        for name in ["two words", " leading", "trailing ", "line\nbreak", "tab\there"] {
            #expect(!ListenBrainzUsername.isPlausible(name), "\(name) should be refused")
        }
    }

    @Test("a slash is refused: it would point the request at another path")
    func slashIsRefused() {
        #expect(!ListenBrainzUsername.isPlausible("user/../admin"))
    }

    @Test("past the length bound it cannot be a real account")
    func tooLong() {
        #expect(!ListenBrainzUsername.isPlausible(String(repeating: "a", count: 41)))
        #expect(ListenBrainzUsername.isPlausible(String(repeating: "a", count: 40)))
    }

    @Test("the name is escaped before it reaches a URL path")
    func pathSegmentEscapes() throws {
        #expect(ListenBrainzUsername.pathSegment("Spartan_K.Kong") == "Spartan_K.Kong")
        let escaped = try #require(ListenBrainzUsername.pathSegment("user name"))
        #expect(!escaped.contains(" "))
        let url = URL(string: "https://api.listenbrainz.org/1/user/\(escaped)/listen-count")
        #expect(url != nil)
    }
}
