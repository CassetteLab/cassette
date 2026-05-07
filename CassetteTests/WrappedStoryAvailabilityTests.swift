// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - File-scope helpers

private func makeDate(
    year: Int, month: Int, day: Int,
    hour: Int = 12, minute: Int = 0, second: Int = 0,
    tzId: String = "UTC"
) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = second
    comps.timeZone = TimeZone(identifier: tzId)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tzId)!
    return cal.date(from: comps)!
}

private func utcCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

private func parisCalendar() -> Calendar {
    // Europe/Paris is UTC+1 in winter (CET), so Dec 27 23:00 UTC = Dec 28 00:00 CET.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    return cal
}

// MARK: - Suite

@Suite("WrappedStoryAvailability")
struct WrappedStoryAvailabilityTests {

    // MARK: Past years — always available

    @Test func pastYear_isAlwaysAvailable() {
        let date = makeDate(year: 2026, month: 1, day: 1)
        #expect(WrappedStoryAvailability.isStoryAvailable(forYear: 2025, currentDate: date, calendar: utcCalendar()))
    }

    @Test func pastYear_earlyInYear_isStillAvailable() {
        let date = makeDate(year: 2026, month: 3, day: 10)
        #expect(WrappedStoryAvailability.isStoryAvailable(forYear: 2024, currentDate: date, calendar: utcCalendar()))
    }

    // MARK: Current year — locked before Dec 28, unlocked on/after

    @Test func currentYear_beforeDec28_notAvailable() {
        let date = makeDate(year: 2026, month: 12, day: 27, hour: 23, minute: 59, second: 59)
        #expect(!WrappedStoryAvailability.isStoryAvailable(forYear: 2026, currentDate: date, calendar: utcCalendar()))
    }

    @Test func currentYear_atMidnightDec28_available() {
        // Boundary: exactly midnight Dec 28 → unlocked
        let date = makeDate(year: 2026, month: 12, day: 28, hour: 0, minute: 0, second: 0)
        #expect(WrappedStoryAvailability.isStoryAvailable(forYear: 2026, currentDate: date, calendar: utcCalendar()))
    }

    @Test func currentYear_afterDec28_available() {
        let date = makeDate(year: 2026, month: 12, day: 30, hour: 15)
        #expect(WrappedStoryAvailability.isStoryAvailable(forYear: 2026, currentDate: date, calendar: utcCalendar()))
    }

    @Test func currentYear_dec31_available() {
        let date = makeDate(year: 2026, month: 12, day: 31, hour: 23, minute: 59)
        #expect(WrappedStoryAvailability.isStoryAvailable(forYear: 2026, currentDate: date, calendar: utcCalendar()))
    }

    // MARK: Future years — never available

    @Test func futureYear_neverAvailable() {
        // Even on Dec 31 of the previous year, the next year is not available
        let date = makeDate(year: 2026, month: 12, day: 31)
        #expect(!WrappedStoryAvailability.isStoryAvailable(forYear: 2027, currentDate: date, calendar: utcCalendar()))
    }

    @Test func futureYear_afterDec28_stillNotAvailable() {
        let date = makeDate(year: 2026, month: 12, day: 29)
        #expect(!WrappedStoryAvailability.isStoryAvailable(forYear: 2027, currentDate: date, calendar: utcCalendar()))
    }

    // MARK: Timezone edge case

    @Test func timezoneEdge_sameInstant_lockedInUTC_unlockedInParis() {
        // Dec 27 2026 23:00 UTC = Dec 28 2026 00:00 CET (Europe/Paris).
        // The same wall-clock instant should lock in UTC but unlock in Paris,
        // confirming the gate respects the injected calendar's timezone.
        let instantAtDec27_23UTC = makeDate(year: 2026, month: 12, day: 27, hour: 23, minute: 0, tzId: "UTC")

        #expect(!WrappedStoryAvailability.isStoryAvailable(
            forYear: 2026,
            currentDate: instantAtDec27_23UTC,
            calendar: utcCalendar()
        ), "Should be locked at 23:00 UTC (still Dec 27 in UTC)")

        #expect(WrappedStoryAvailability.isStoryAvailable(
            forYear: 2026,
            currentDate: instantAtDec27_23UTC,
            calendar: parisCalendar()
        ), "Should be unlocked at 00:00 CET (already Dec 28 in Paris)")
    }
}
