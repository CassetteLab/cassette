// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
@testable import Cassette

// Locks the auto-extend trigger decision — in particular that an Instant Mix assembling behind its
// lone seed does NOT let an already-enabled endless mode backfill generic library tracks into the gap.

@Suite("Auto-extend gate")
struct AutoExtendGateTests {

    @Test("fires when enabled, no loop/radio, and few tracks remain")
    func firesOnLowRemaining() {
        #expect(PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .off, hasRadio: false, isBuildingInstantMix: false, remaining: 0
        ))
        #expect(PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .off, hasRadio: false, isBuildingInstantMix: false, remaining: 15
        ))
    }

    @Test("stays quiet while a plentiful queue remains")
    func quietWhenPlentyRemains() {
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .off, hasRadio: false, isBuildingInstantMix: false, remaining: 16
        ))
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .off, hasRadio: false, isBuildingInstantMix: false, remaining: 99
        ))
    }

    @Test("an assembling Instant Mix suppresses the backfill even with a lone seed")
    func instantMixBuildSuppresses() {
        // The exact bug: endless already on (isEnabled), seed alone (remaining 0) — must NOT fire
        // while the mix is still being built behind it, or 50 library tracks jump the queue.
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .off, hasRadio: false, isBuildingInstantMix: true, remaining: 0
        ))
    }

    @Test("disabled, a loop mode, or an active radio each hold it back")
    func otherGuards() {
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: false, repeatMode: .off, hasRadio: false, isBuildingInstantMix: false, remaining: 0
        ))
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .all, hasRadio: false, isBuildingInstantMix: false, remaining: 0
        ))
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .one, hasRadio: false, isBuildingInstantMix: false, remaining: 0
        ))
        #expect(!PlayerService.shouldAutoExtend(
            isEnabled: true, repeatMode: .off, hasRadio: true, isBuildingInstantMix: false, remaining: 0
        ))
    }
}
