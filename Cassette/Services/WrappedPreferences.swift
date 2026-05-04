// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

// MARK: - YearMonth

/// A year-month pair used to track Wrapped update state.
/// Comparable so ranges of months can be derived easily.
nonisolated struct YearMonth: Comparable, Hashable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int

    var description: String { String(format: "%04d-%02d", year, month) }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              m >= 1 && m <= 12 else { return nil }
        year = y
        month = m
    }

    /// Returns the YearMonth offset by `months` (negative values go backward).
    func advanced(by months: Int) -> YearMonth {
        let total = (year - 1) * 12 + (month - 1) + months
        return YearMonth(year: total / 12 + 1, month: total % 12 + 1)
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        lhs.year != rhs.year ? lhs.year < rhs.year : lhs.month < rhs.month
    }
}

// MARK: - WrappedPreferences

/// Thin UserDefaults wrapper for Wrapped playlist service state.
/// All keys are namespaced under "cassette.wrapped." and scoped per-server.
/// Thread-safe: UserDefaults is documented thread-safe for get/set operations.
nonisolated struct WrappedPreferences: Sendable {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    private static func lastMonthKey(_ serverId: String) -> String {
        "cassette.wrapped.lastUpdatedMonth.\(serverId)"
    }

    private static func playlistIdKey(_ year: Int, _ serverId: String) -> String {
        "cassette.wrapped.playlistId.\(year).\(serverId)"
    }

    private static func lastYearKey(_ serverId: String) -> String {
        "cassette.wrapped.lastYear.\(serverId)"
    }

    // MARK: - Last updated month

    func lastUpdatedMonth(serverId: String) -> YearMonth? {
        guard let raw = userDefaults.string(forKey: Self.lastMonthKey(serverId)) else { return nil }
        return YearMonth(string: raw)
    }

    func setLastUpdatedMonth(_ ym: YearMonth, serverId: String) {
        userDefaults.set(ym.description, forKey: Self.lastMonthKey(serverId))
    }

    func clearLastUpdatedMonth(serverId: String) {
        userDefaults.removeObject(forKey: Self.lastMonthKey(serverId))
    }

    // MARK: - Annual playlist ID cache

    func playlistId(year: Int, serverId: String) -> String? {
        userDefaults.string(forKey: Self.playlistIdKey(year, serverId))
    }

    func setPlaylistId(_ id: String, year: Int, serverId: String) {
        userDefaults.set(id, forKey: Self.playlistIdKey(year, serverId))
    }

    // MARK: - Last known year marker

    func lastWrappedYear(serverId: String) -> Int? {
        let v = userDefaults.integer(forKey: Self.lastYearKey(serverId))
        return v == 0 ? nil : v
    }

    func setLastWrappedYear(_ year: Int, serverId: String) {
        userDefaults.set(year, forKey: Self.lastYearKey(serverId))
    }
}
