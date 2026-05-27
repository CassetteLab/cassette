// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

/// Records and manages local playback events for Wrapped statistics.
///
/// Pure actor — no MainActor, no singleton, no network access.
/// Injected via AppContainer. All persistence uses a private ModelContext;
/// PlaybackEvent PersistentModel instances never leave this actor.
actor StatsService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    func recordPlayback(_ event: PlaybackEventDTO, trigger: String = "") async {
        let context = ModelContext(modelContainer)
        let model = PlaybackEvent(
            trackId: event.trackId,
            trackTitle: event.trackTitle,
            albumId: event.albumId,
            albumTitle: event.albumTitle,
            artistId: event.artistId,
            artistName: event.artistName,
            genre: event.genre,
            timestamp: event.timestamp,
            durationListened: event.durationListened,
            trackDuration: event.trackDuration,
            wasCompleted: event.wasCompleted,
            serverId: event.serverId
        )
        context.insert(model)
        do {
            try context.save()
            let artistIdForLog = event.artistId ?? "nil"
            let durationForLog = String(format: "%.1f", event.durationListened)
            Logger.stats.debug(
                "[INSERT] trigger=\(trigger, privacy: .public) trackId=\(event.trackId, privacy: .public) artistId=\(artistIdForLog, privacy: .public) durationListened=\(durationForLog, privacy: .public)s startedAt=\(event.timestamp, privacy: .public) completed=\(event.wasCompleted, privacy: .public) serverId=\(event.serverId, privacy: .public)"
            )
        } catch {
            Logger.stats.error("Failed to save playback event: \(error, privacy: .public)")
        }
    }

    func eventCount(forServer serverId: String) async -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func deleteAllEvents(forServer serverId: String) async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        do {
            let events = try context.fetch(descriptor)
            guard !events.isEmpty else { return }
            for event in events {
                context.delete(event)
            }
            try context.save()
            Logger.stats.info("Deleted \(events.count) event(s) for serverId=\(serverId, privacy: .public)")
        } catch {
            Logger.stats.error("Failed to delete events for serverId=\(serverId, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Phase 2: Wrapped aggregation

    func hasEventsInPeriod(_ period: WrappedPeriod, serverId: String, calendar: Calendar) async -> Bool {
        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func wrappedData(for period: WrappedPeriod, serverId: String, calendar: Calendar) async -> WrappedData {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif

        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )

        let events: [PlaybackEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            Logger.stats.error("wrappedData fetch failed for serverId=\(sid, privacy: .public): \(error, privacy: .public)")
            events = []
        }

        let data = aggregate(events: events, period: period, serverId: serverId, periodRange: range, calendar: calendar)

        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Logger.stats.debug(
            "wrappedData: \(events.count, privacy: .public) events aggregated in \(String(format: "%.1f", elapsed * 1000), privacy: .public)ms period=\(period.displayName, privacy: .public)"
        )
        #endif

        return data
    }

    func topTracks(forPeriod period: WrappedPeriod, serverId: String, limit: Int, calendar: Calendar) async -> [TopTrackEntry] {
        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )
        let events: [PlaybackEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            Logger.stats.error("topTracks fetch failed for serverId=\(sid, privacy: .public): \(error, privacy: .public)")
            return []
        }
        guard !events.isEmpty else { return [] }
        var groups: [String: (duration: TimeInterval, count: Int, title: String, artist: String, album: String?)] = [:]
        for e in events {
            let d = effectiveDuration(for: e)
            if var g = groups[e.trackId] {
                g.duration += d
                g.count += 1
                groups[e.trackId] = g
            } else {
                groups[e.trackId] = (d, 1, e.trackTitle, e.artistName, e.albumTitle)
            }
        }
        let sorted = groups.sorted {
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            return $0.key < $1.key
        }
        return sorted.prefix(limit).enumerated().map { idx, pair in
            TopTrackEntry(
                rank: idx + 1,
                trackId: pair.key,
                title: pair.value.title,
                artistName: pair.value.artist,
                albumTitle: pair.value.album,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count
            )
        }
    }

    // MARK: - Private aggregation

    private func aggregate(
        events: [PlaybackEvent],
        period: WrappedPeriod,
        serverId: String,
        periodRange: (start: Date, end: Date),
        calendar: Calendar
    ) -> WrappedData {
        guard !events.isEmpty else {
            return WrappedData(
                period: period, serverId: serverId, generatedAt: Date(),
                totalSecondsListened: 0, totalTracksPlayed: 0,
                totalUniqueTracks: 0, totalUniqueArtists: 0, totalUniqueAlbums: 0,
                topTracks: [], topAlbums: [], topArtists: [],
                dominantGenre: nil, streakDays: 0,
                firstTrackOfPeriod: nil, lastTrackOfPeriod: nil
            )
        }

        let totalSecondsListened = events.reduce(0.0) { $0 + effectiveDuration(for: $1) }
        let totalUniqueTracks = Set(events.map(\.trackId)).count
        let totalUniqueArtists = Set(events.compactMap(\.artistId)).count
        let totalUniqueAlbums = Set(events.compactMap(\.albumId)).count

        let topTracks = buildTopTracks(from: events)
        let topAlbums = buildTopAlbums(from: events)
        let topArtists = buildTopArtists(from: events)
        let dominantGenre = buildDominantGenre(from: events)
        let streak = buildStreak(from: events, periodRange: periodRange, calendar: calendar)
        let (first, last) = buildFirstLast(from: events)

        return WrappedData(
            period: period,
            serverId: serverId,
            generatedAt: Date(),
            totalSecondsListened: totalSecondsListened,
            totalTracksPlayed: events.count,
            totalUniqueTracks: totalUniqueTracks,
            totalUniqueArtists: totalUniqueArtists,
            totalUniqueAlbums: totalUniqueAlbums,
            topTracks: topTracks,
            topAlbums: topAlbums,
            topArtists: topArtists,
            dominantGenre: dominantGenre,
            streakDays: streak,
            firstTrackOfPeriod: first,
            lastTrackOfPeriod: last
        )
    }

    private func buildTopTracks(from events: [PlaybackEvent]) -> [TopTrackEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, title: String, artist: String, album: String?)] = [:]
        for e in events {
            let d = effectiveDuration(for: e)
            if var g = groups[e.trackId] {
                g.duration += d
                g.count += 1
                groups[e.trackId] = g
            } else {
                groups[e.trackId] = (d, 1, e.trackTitle, e.artistName, e.albumTitle)
            }
        }
        // Primary: playCount — reflects actual listening intent; loop time is tiebreaker.
        let sorted = groups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            return $0.key < $1.key
        }
        return sorted.prefix(10).enumerated().map { idx, pair in
            TopTrackEntry(
                rank: idx + 1,
                trackId: pair.key,
                title: pair.value.title,
                artistName: pair.value.artist,
                albumTitle: pair.value.album,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count
            )
        }
    }

    private func buildTopAlbums(from events: [PlaybackEvent]) -> [TopAlbumEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, tracks: Set<String>, title: String, artist: String)] = [:]
        for e in events {
            guard let albumId = e.albumId else { continue }
            let d = effectiveDuration(for: e)
            if var g = groups[albumId] {
                g.duration += d
                g.count += 1
                g.tracks.insert(e.trackId)
                groups[albumId] = g
            } else {
                groups[albumId] = (d, 1, [e.trackId], e.albumTitle ?? "", e.artistName)
            }
        }
        // Primary: playCount; tiebreaker: totalSecondsListened.
        let sorted = groups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            return $0.key < $1.key
        }
        return sorted.prefix(10).enumerated().map { idx, pair in
            TopAlbumEntry(
                rank: idx + 1,
                albumId: pair.key,
                title: pair.value.title,
                artistName: pair.value.artist,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count,
                uniqueTracks: pair.value.tracks.count
            )
        }
    }

    private func buildTopArtists(from events: [PlaybackEvent]) -> [TopArtistEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, tracks: Set<String>, name: String)] = [:]
        for e in events {
            guard let artistId = e.artistId else { continue }
            let d = effectiveDuration(for: e)
            if var g = groups[artistId] {
                g.duration += d
                g.count += 1
                g.tracks.insert(e.trackId)
                groups[artistId] = g
            } else {
                groups[artistId] = (d, 1, [e.trackId], e.artistName)
            }
        }
        // Primary: totalSecondsListened; tiebreaker: playCount.
        let sorted = groups.sorted {
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }
        return sorted.prefix(10).enumerated().map { idx, pair in
            TopArtistEntry(
                rank: idx + 1,
                artistId: pair.key,
                name: pair.value.name,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count,
                uniqueTracks: pair.value.tracks.count
            )
        }
    }

    private func buildDominantGenre(from events: [PlaybackEvent]) -> String? {
        var durations: [String: TimeInterval] = [:]
        for e in events {
            guard let genre = e.genre else { continue }
            durations[genre, default: 0] += effectiveDuration(for: e)
        }
        guard !durations.isEmpty else { return nil }
        return durations.max {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key > $1.key
        }?.key
    }

    private func buildStreak(
        from events: [PlaybackEvent],
        periodRange: (start: Date, end: Date),
        calendar: Calendar
    ) -> Int {
        let eventDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        let today = calendar.startOfDay(for: Date())
        let referenceDay: Date
        if today >= periodRange.start && today < periodRange.end {
            referenceDay = today
        } else {
            // Period is in the past: use last day of period
            let lastInstant = calendar.date(byAdding: .second, value: -1, to: periodRange.end)!
            referenceDay = calendar.startOfDay(for: lastInstant)
        }
        guard eventDays.contains(referenceDay) else { return 0 }
        var streak = 0
        var day = referenceDay
        while eventDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Caps a single event's contribution at its track duration.
    /// Prevents wall-clock inflation (paused time counted as listened time) from
    /// distorting Wrapped totals for existing data. Falls back to a 600 s ceiling
    /// when trackDuration was not recorded (value of 0).
    private func effectiveDuration(for event: PlaybackEvent) -> TimeInterval {
        guard event.trackDuration > 0 else {
            return min(event.durationListened, 600)
        }
        return min(event.durationListened, event.trackDuration)
    }

    private func buildFirstLast(from events: [PlaybackEvent]) -> (first: TopTrackEntry?, last: TopTrackEntry?) {
        guard !events.isEmpty,
              let earliest = events.min(by: { $0.timestamp < $1.timestamp }),
              let latest = events.max(by: { $0.timestamp < $1.timestamp })
        else { return (nil, nil) }
        let first = TopTrackEntry(
            rank: 0, trackId: earliest.trackId, title: earliest.trackTitle,
            artistName: earliest.artistName, albumTitle: earliest.albumTitle,
            totalSecondsListened: effectiveDuration(for: earliest), playCount: 1
        )
        let last = TopTrackEntry(
            rank: 0, trackId: latest.trackId, title: latest.trackTitle,
            artistName: latest.artistName, albumTitle: latest.albumTitle,
            totalSecondsListened: effectiveDuration(for: latest), playCount: 1
        )
        return (first, last)
    }
}
