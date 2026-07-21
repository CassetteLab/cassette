// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

/// The one property that matters after the AudioMuse feedback: Instant Mix must reflect the
/// server's similarity ORDER, never a reshuffled one.
@Suite("Instant Mix — assembly preserves server order")
struct InstantMixAssemblyTests {

    private func mk(_ ids: [String]) throws -> [Song] {
        try ids.map { id in
            try JSONDecoder().decode(Song.self, from: Data(#"{"id":"\#(id)","title":"\#(id)","isDir":false}"#.utf8))
        }
    }

    @Test("the base order is preserved exactly")
    func baseOrderPreserved() throws {
        let base = try mk(["a", "b", "c", "d"])
        let result = LibraryService.assembleMix(base: base, expansions: [], count: 100)
        #expect(result.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test("expansions are appended behind the base, never interleaved")
    func expansionsGoToTheTail() throws {
        let base = try mk(["a", "b", "c"])
        let expansions = try mk(["x", "y"])
        let result = LibraryService.assembleMix(base: base, expansions: expansions, count: 100)
        #expect(result.map(\.id) == ["a", "b", "c", "x", "y"])
    }

    @Test("duplicates are dropped keeping the first (base) occurrence and its position")
    func dedupKeepsBasePosition() throws {
        let base = try mk(["a", "b", "c"])
        // "b" reappears in the expansions and must NOT move or duplicate.
        let expansions = try mk(["b", "x", "a", "y"])
        let result = LibraryService.assembleMix(base: base, expansions: expansions, count: 100)
        #expect(result.map(\.id) == ["a", "b", "c", "x", "y"])
    }

    @Test("the result is trimmed to count without reordering")
    func trimsToCount() throws {
        let base = try mk(["a", "b", "c", "d", "e"])
        let result = LibraryService.assembleMix(base: base, expansions: [], count: 3)
        #expect(result.map(\.id) == ["a", "b", "c"])
    }

    @Test("a full base is returned verbatim — the AudioMuse case")
    func fullBaseIsVerbatim() throws {
        // 100 tracks in a deliberately non-artist-grouped order, as a good similarity service returns.
        let ids = (0..<100).map { "t\($0)" }
        let base = try mk(ids)
        let result = LibraryService.assembleMix(base: base, expansions: try mk(["z1", "z2"]), count: 100)
        // Expansions never even appear: the base already fills the count, in its exact order.
        #expect(result.map(\.id) == ids)
    }
}
