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
}
