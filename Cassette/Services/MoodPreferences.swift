// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

// MARK: - Weekly cycle

/// The weekly refresh cadence for mood playlists.
///
/// A "cycle" is the week beginning on the most recent Wednesday. Anchoring on a Wednesday rather
/// than counting seven days from the last run keeps the refresh on a stable weekday instead of
/// drifting later every week by however long the user took to open the app.
nonisolated enum MoodCycle {
    /// Gregorian weekday number for Wednesday (Sunday is 1).
    static let refreshWeekday = 4

    /// Start of the cycle `date` falls in: midnight on the most recent Wednesday at or before it.
    ///
    /// A playlist is due when its recorded cycle is older than this. Note what that means in
    /// practice on iOS: background execution is never guaranteed, so the refresh happens on the
    /// first launch on or after Wednesday, not at a fixed hour. The UI must therefore show the date
    /// of the last refresh rather than promise a schedule.
    static func start(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceWednesday = (weekday - refreshWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysSinceWednesday, to: startOfDay) ?? startOfDay
    }
}

// MARK: - MoodPreferences

/// UserDefaults state for the mood playlists, namespaced under `cassette.mood.` and scoped per
/// server. Mirrors WrappedPreferences.
///
/// The synced-cycle marker is per MOOD, not per run. That is what makes a partial failure safe: a
/// mood that could not be refreshed keeps its previous playlist and its old marker, so it retries
/// on the next launch while the four that succeeded stay done.
nonisolated struct MoodPreferences: Sendable {
    private nonisolated(unsafe) let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    private static func cycleKey(_ mood: Mood, _ serverId: String) -> String {
        "cassette.mood.syncedCycle.\(mood.rawValue).\(serverId)"
    }
    private static func playlistIdKey(_ mood: Mood, _ serverId: String) -> String {
        "cassette.mood.playlistId.\(mood.rawValue).\(serverId)"
    }
    private static func lastAttemptKey(_ serverId: String) -> String {
        "cassette.mood.lastAttempt.\(serverId)"
    }
    private static func lastSourceKey(_ serverId: String) -> String {
        "cassette.mood.lastSource.\(serverId)"
    }
    private static func coverKey(_ mood: Mood, _ serverId: String) -> String {
        "cassette.mood.coverApplied.\(mood.rawValue).\(serverId)"
    }

    // MARK: - Per-mood cycle marker

    func syncedCycle(mood: Mood, serverId: String) -> Date? {
        let raw = userDefaults.double(forKey: Self.cycleKey(mood, serverId))
        return raw == 0 ? nil : Date(timeIntervalSinceReferenceDate: raw)
    }

    func setSyncedCycle(_ date: Date, mood: Mood, serverId: String) {
        userDefaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.cycleKey(mood, serverId))
    }

    /// Most recent refresh across all five moods — what the UI shows, since "updated Wednesday"
    /// would be a promise the platform cannot keep.
    func lastRefresh(serverId: String) -> Date? {
        Mood.allCases.compactMap { syncedCycle(mood: $0, serverId: serverId) }.max()
    }

    // MARK: - Playlist id cache

    func playlistId(mood: Mood, serverId: String) -> String? {
        userDefaults.string(forKey: Self.playlistIdKey(mood, serverId))
    }

    func setPlaylistId(_ id: String, mood: Mood, serverId: String) {
        userDefaults.set(id, forKey: Self.playlistIdKey(mood, serverId))
    }

    // MARK: - Attempt throttle

    /// Timestamp of the last sync attempt, successful or not. Guards against a permanently
    /// unreachable AudioMuse instance costing five slow HTTP calls on every single launch.
    func lastAttempt(serverId: String) -> Date? {
        let raw = userDefaults.double(forKey: Self.lastAttemptKey(serverId))
        return raw == 0 ? nil : Date(timeIntervalSinceReferenceDate: raw)
    }

    func setLastAttempt(_ date: Date, serverId: String) {
        userDefaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.lastAttemptKey(serverId))
    }

    // MARK: - Cover

    /// Whether this mood's playlist already carries its generated cover. Tracked so the cover is
    /// rendered and uploaded once rather than on every weekly refresh.
    func hasCover(mood: Mood, serverId: String) -> Bool {
        userDefaults.bool(forKey: Self.coverKey(mood, serverId))
    }

    func setHasCover(mood: Mood, serverId: String) {
        userDefaults.set(true, forKey: Self.coverKey(mood, serverId))
    }

    // MARK: - Source

    /// Which provider last populated the playlists, so the UI can say whether the user is getting
    /// sonic matching or the weaker tag matching.
    func lastSource(serverId: String) -> MoodSourceKind? {
        userDefaults.string(forKey: Self.lastSourceKey(serverId)).flatMap(MoodSourceKind.init(rawValue:))
    }

    func setLastSource(_ kind: MoodSourceKind, serverId: String) {
        userDefaults.set(kind.rawValue, forKey: Self.lastSourceKey(serverId))
    }

    // MARK: - Forcing a rebuild

    /// Marks every mood as due again without touching the playlist ids, so a rebuild rewrites the
    /// playlists the user already has rather than leaving five orphans behind.
    ///
    /// Used when the track source changes — connecting AudioMuse should not mean waiting until
    /// Wednesday to hear the difference.
    func markAllDue(serverId: String) {
        for mood in Mood.allCases {
            userDefaults.removeObject(forKey: Self.cycleKey(mood, serverId))
        }
        userDefaults.removeObject(forKey: Self.lastAttemptKey(serverId))
    }

    // MARK: - Teardown

    /// Forgets everything for a server — used when the user disconnects AudioMuse, so reconnecting
    /// rebuilds rather than trusting stale playlist ids.
    func reset(serverId: String) {
        for mood in Mood.allCases {
            userDefaults.removeObject(forKey: Self.cycleKey(mood, serverId))
            userDefaults.removeObject(forKey: Self.playlistIdKey(mood, serverId))
            userDefaults.removeObject(forKey: Self.coverKey(mood, serverId))
        }
        userDefaults.removeObject(forKey: Self.lastAttemptKey(serverId))
        userDefaults.removeObject(forKey: Self.lastSourceKey(serverId))
    }
}
