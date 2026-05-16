// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// Determines when an annual Wrapped becomes available.
/// Annual Wrapped for year N unlocks on December 28 of year N.
nonisolated enum WrappedAvailability {

    /// Returns `true` if the annual Wrapped for `year` should be shown given `currentDate`.
    static func isAnnualAvailable(
        year: Int,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let threshold = calendar.date(from: DateComponents(year: year, month: 12, day: 28)) else {
            return false
        }
        return currentDate >= threshold
    }
}
