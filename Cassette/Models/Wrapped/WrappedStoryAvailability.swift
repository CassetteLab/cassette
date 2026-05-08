// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Determines whether the cinematic story player (and share) is unlocked for a given Wrapped year.
///
/// Rules:
/// - Past years are always available.
/// - Future years are never available.
/// - The current year unlocks on December 28 at midnight **in the user's local timezone**
///   (controlled by the injected `calendar`).
struct WrappedStoryAvailability {

    /// Returns `true` if the story playback is unlocked for `year` given `currentDate`.
    ///
    /// `calendar` controls timezone interpretation; pass `.current` in production,
    /// inject a fixed-timezone calendar in tests.
    static func isStoryAvailable(
        forYear year: Int,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let currentYear = calendar.component(.year, from: currentDate)
        if year < currentYear { return true }
        if year > currentYear { return false }
        guard let unlockDate = calendar.date(from: DateComponents(year: year, month: 12, day: 28)) else {
            return false
        }
        return currentDate >= unlockDate
    }

    /// Returns `true` if the current-year Wrapped card should be shown in the Discover carousel.
    ///
    /// Window: December 3 N (inclusive) → January 1 N+1 (exclusive).
    static func isWrappedCardVisible(
        forYear year: Int,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let cardStart = calendar.date(from: DateComponents(year: year, month: 12, day: 3)),
              let cardEnd   = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return false }
        return currentDate >= cardStart && currentDate < cardEnd
    }

    /// Days remaining (from start-of-today) until the December 28 story unlock.
    ///
    /// Returns `nil` for any year that isn't the current calendar year.
    /// Returns 0 on unlock day, negative values after unlock.
    static func daysUntilStoryUnlock(
        forYear year: Int,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        let currentYear = calendar.component(.year, from: currentDate)
        guard year == currentYear else { return nil }
        guard let unlockDate = calendar.date(from: DateComponents(year: year, month: 12, day: 28)) else { return nil }
        let startOfToday  = calendar.startOfDay(for: currentDate)
        let startOfUnlock = calendar.startOfDay(for: unlockDate)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfUnlock).day
    }
}
