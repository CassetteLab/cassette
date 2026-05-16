// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

// MARK: - Helpers

private func makeService() throws -> StatsService {
    let container = try ModelContainer.cassette(inMemory: true)
    return StatsService(modelContainer: container)
}

/// Builds a Date at the given components in the given timezone.
private func dateIn(
    _ timezone: TimeZone,
    year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0
) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timezone
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day
    c.hour = hour; c.minute = minute; c.second = 0
    return cal.date(from: c)!
}

private let utcTZ = TimeZone(identifier: "UTC")!
private let parisTZ = TimeZone(identifier: "Europe/Paris")!

private func utcCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = utcTZ
    return cal
}

private func parisCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = parisTZ
    return cal
}

private func makeDTO(
    trackId: String = "t1",
    timestamp: Date,
    durationListened: TimeInterval = 180,
    serverId: String = "srv"
) -> PlaybackEventDTO {
    PlaybackEventDTO(
        trackId: trackId,
        trackTitle: "Track",
        albumId: nil,
        albumTitle: nil,
        artistId: nil,
        artistName: "Artist",
        genre: nil,
        timestamp: timestamp,
        durationListened: durationListened,
        trackDuration: 200,
        wasCompleted: true,
        serverId: serverId
    )
}

// MARK: - Suite

/// Streak tests use a fixed past period so "today" is always outside the
/// period range — this makes the reference day deterministic without
/// depending on the system clock.
@Suite("WrappedStreak")
struct WrappedStreakTests {

    // h) 5 consecutive days including the last day of the period → streak = 5
    @Test func streak_fiveConsecutiveDays_returnsfive() async throws {
        let service = try makeService()
        let cal = utcCalendar()
        // Period: January 2025 (past). Last day = Jan 31.
        for day in 27...31 {
            await service.recordPlayback(makeDTO(
                trackId: "t\(day)",
                timestamp: dateIn(utcTZ, year: 2025, month: 1, day: day)
            ))
        }
        let data = await service.wrappedData(
            for: .month(year: 2025, month: 1), serverId: "srv", calendar: cal
        )
        #expect(data.streakDays == 5)
    }

    // i) Gap yesterday (from last day of period) → streak = 1
    @Test func streak_gapOneDayBeforeEnd_returnsOne() async throws {
        let service = try makeService()
        let cal = utcCalendar()
        // Jan 31 has an event, Jan 30 doesn't, Jan 29 has one
        await service.recordPlayback(makeDTO(
            trackId: "t31",
            timestamp: dateIn(utcTZ, year: 2025, month: 1, day: 31)
        ))
        await service.recordPlayback(makeDTO(
            trackId: "t29",
            timestamp: dateIn(utcTZ, year: 2025, month: 1, day: 29)
        ))

        let data = await service.wrappedData(
            for: .month(year: 2025, month: 1), serverId: "srv", calendar: cal
        )
        // Streak from Jan 31 backwards: Jan 31 ✓, Jan 30 ✗ → streak = 1
        #expect(data.streakDays == 1)
    }

    // j) No event on last day of period → streak = 0
    @Test func streak_noEventOnReferenceDay_returnsZero() async throws {
        let service = try makeService()
        let cal = utcCalendar()
        // Events only on Jan 28 and 29, not on Jan 31 (last day)
        await service.recordPlayback(makeDTO(
            trackId: "t28",
            timestamp: dateIn(utcTZ, year: 2025, month: 1, day: 28)
        ))
        await service.recordPlayback(makeDTO(
            trackId: "t29",
            timestamp: dateIn(utcTZ, year: 2025, month: 1, day: 29)
        ))

        let data = await service.wrappedData(
            for: .month(year: 2025, month: 1), serverId: "srv", calendar: cal
        )
        #expect(data.streakDays == 0)
    }

    // k) Timezone sensitivity: an event at 23:30 UTC on Jan 31 is
    //    still Jan 31 in UTC but Feb 1 in UTC+2. Verify that using
    //    Europe/Paris calendar changes which day the event belongs to.
    @Test func streak_timezoneAffectsDay() async throws {
        let service = try makeService()
        // Event at 2025-01-31 23:30 UTC = 2025-02-01 00:30 Europe/Paris
        let eventTime = dateIn(utcTZ, year: 2025, month: 1, day: 31, hour: 23, minute: 30)

        // Record only this one event
        await service.recordPlayback(makeDTO(trackId: "late", timestamp: eventTime))

        // With UTC calendar: event is on Jan 31 → last day of January → streak = 1
        let dataUTC = await service.wrappedData(
            for: .month(year: 2025, month: 1), serverId: "srv", calendar: utcCalendar()
        )
        #expect(dataUTC.streakDays == 1)

        // With Europe/Paris calendar: same event is on Feb 1, outside Jan → streak = 0
        let dataParis = await service.wrappedData(
            for: .month(year: 2025, month: 1), serverId: "srv", calendar: parisCalendar()
        )
        #expect(dataParis.streakDays == 0)
    }

    // Streak for a year period: 3 consecutive days at year-end → streak = 3
    @Test func streak_yearPeriod_threeConsecutiveDaysAtYearEnd() async throws {
        let service = try makeService()
        let cal = utcCalendar()
        for day in 29...31 {
            await service.recordPlayback(makeDTO(
                trackId: "d\(day)",
                timestamp: dateIn(utcTZ, year: 2025, month: 12, day: day)
            ))
        }
        let data = await service.wrappedData(
            for: .year(2025), serverId: "srv", calendar: cal
        )
        #expect(data.streakDays == 3)
    }

    // Streak: multiple events same day count as one streak day
    @Test func streak_multipleEventsPerDay_countAsOneStreakDay() async throws {
        let service = try makeService()
        let cal = utcCalendar()
        // Three events on Jan 31, two on Jan 30
        for hour in [9, 14, 20] {
            await service.recordPlayback(makeDTO(
                trackId: "jan31h\(hour)",
                timestamp: dateIn(utcTZ, year: 2025, month: 1, day: 31, hour: hour)
            ))
        }
        for hour in [10, 18] {
            await service.recordPlayback(makeDTO(
                trackId: "jan30h\(hour)",
                timestamp: dateIn(utcTZ, year: 2025, month: 1, day: 30, hour: hour)
            ))
        }
        let data = await service.wrappedData(
            for: .month(year: 2025, month: 1), serverId: "srv", calendar: cal
        )
        #expect(data.streakDays == 2)
    }

    // WrappedPeriod helpers
    @Test func wrappedPeriod_dateRange_month() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utcTZ
        let range = WrappedPeriod.month(year: 2026, month: 3).dateRange(in: cal)

        var startComponents = DateComponents()
        startComponents.year = 2026; startComponents.month = 3; startComponents.day = 1
        startComponents.hour = 0; startComponents.minute = 0; startComponents.second = 0
        startComponents.timeZone = utcTZ
        let expectedStart = cal.date(from: startComponents)!

        var endComponents = DateComponents()
        endComponents.year = 2026; endComponents.month = 4; endComponents.day = 1
        endComponents.hour = 0; endComponents.minute = 0; endComponents.second = 0
        endComponents.timeZone = utcTZ
        let expectedEnd = cal.date(from: endComponents)!

        #expect(range.start == expectedStart)
        #expect(range.end == expectedEnd)
    }

    @Test func wrappedPeriod_dateRange_year() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utcTZ
        let range = WrappedPeriod.year(2025).dateRange(in: cal)

        var startC = DateComponents()
        startC.year = 2025; startC.month = 1; startC.day = 1
        startC.hour = 0; startC.minute = 0; startC.second = 0; startC.timeZone = utcTZ
        var endC = DateComponents()
        endC.year = 2026; endC.month = 1; endC.day = 1
        endC.hour = 0; endC.minute = 0; endC.second = 0; endC.timeZone = utcTZ

        #expect(range.start == cal.date(from: startC)!)
        #expect(range.end == cal.date(from: endC)!)
    }

    @Test func wrappedPeriod_displayName_month() {
        // displayName uses Calendar.current locale, just verify it contains year
        let name = WrappedPeriod.month(year: 2026, month: 11).displayName
        #expect(name.contains("2026"))
    }

    @Test func wrappedPeriod_displayName_year() {
        #expect(WrappedPeriod.year(2025).displayName == "2025")
    }
}
