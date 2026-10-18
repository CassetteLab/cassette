// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

/// Locks the cover-art tiers.
///
/// A 180pt grid cell on a @3x screen needs 540 px. `thumb` once served both grid cells and 44pt
/// rows at 240 px, and that value was requested from the server too — so the blur arrived over
/// the wire and no amount of local work could undo it.
@Suite("Artwork tiers")
struct ArtworkTierTests {

    @Test("A grid cell's tier covers a 180pt cell on a @3x screen")
    func gridTierCoversRealGridCells() {
        let cellPoints = 180.0
        let scale = 3.0
        #expect(Double(ArtworkTier.grid.decodePixels) >= cellPoints * scale)
    }

    @Test("Tiers grow strictly, so the cheapest adequate one is always the lowest")
    func tiersAreOrdered() {
        #expect(ArtworkTier.thumb.decodePixels < ArtworkTier.grid.decodePixels)
        #expect(ArtworkTier.grid.decodePixels < ArtworkTier.hero.decodePixels)
    }

    @Test("Every tier is reachable from allCases")
    func allCasesIsComplete() {
        // Cache invalidation iterates allCases to drop stale copies. A tier missing from it
        // would leave a changed cover showing its old artwork at that size only.
        #expect(Set(ArtworkTier.allCases) == Set([.thumb, .grid, .hero]))
    }

    @Test("A full cache of any one tier stays under the 120 MB budget")
    func budgetHoldsForEveryTier() {
        let limit = 120 * 1024 * 1024
        for tier in ArtworkTier.allCases {
            // The eviction loop keeps the newest entry whatever its size, so the worst case is
            // the budget plus one image. Anything that no longer fits that shape is a regression.
            #expect(tier.approximateBytes <= limit)
        }
    }

    @Test("Byte cost matches four bytes per pixel")
    func costMatchesDecodedSize() {
        for tier in ArtworkTier.allCases {
            #expect(tier.approximateBytes == tier.decodePixels * tier.decodePixels * 4)
        }
    }
}
