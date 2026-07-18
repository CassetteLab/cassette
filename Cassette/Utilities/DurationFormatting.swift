// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

extension TimeInterval {
    /// Returns (number, unit) for Wrapped stat hero display.
    func wrappedHeroFormat() -> (number: String, unit: String) {
        let totalMinutes = Int(self / 60)
        if totalMinutes < 60 {
            return ("\(totalMinutes)", totalMinutes == 1 ? String(localized: "minute listened") : String(localized: "minutes listened"))
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes > 0 {
            return ("\(hours)h \(minutes)m", String(localized: "listened"))
        }
        return ("\(hours)", hours == 1 ? String(localized: "hour listened") : String(localized: "hours listened"))
    }

    /// Returns (number, unit) for Wrapped stat hero display — always in minutes.
    /// Uses a non-breaking space (U+00A0) as thousands separator to avoid locale bugs.
    func wrappedHeroMinutesFormat() -> (number: String, unit: String) {
        let totalMinutes = max(0, Int(self / 60))
        let formatter = NumberFormatter()
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "\u{00A0}"
        formatter.groupingSize = 3
        let number = formatter.string(from: totalMinutes as NSNumber) ?? "\(totalMinutes)"
        let unit = totalMinutes == 1 ? String(localized: "minute listened") : String(localized: "minutes listened")
        return (number, unit)
    }

    /// Short compact label for secondary display ("42m", "2h 15m", "3h").
    func wrappedCompactLabel() -> String {
        let totalMinutes = Int(self / 60)
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}
