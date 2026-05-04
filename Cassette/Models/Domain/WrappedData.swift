// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

// MARK: - WrappedPeriod

nonisolated enum WrappedPeriod: Sendable, Hashable {
    case month(year: Int, month: Int)
    case year(Int)

    func dateRange(in calendar: Calendar) -> (start: Date, end: Date) {
        switch self {
        case let .month(year, month):
            var startComponents = DateComponents()
            startComponents.year = year
            startComponents.month = month
            startComponents.day = 1
            startComponents.hour = 0
            startComponents.minute = 0
            startComponents.second = 0
            let start = calendar.date(from: startComponents)!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case let .year(year):
            var startComponents = DateComponents()
            startComponents.year = year
            startComponents.month = 1
            startComponents.day = 1
            startComponents.hour = 0
            startComponents.minute = 0
            startComponents.second = 0
            let start = calendar.date(from: startComponents)!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }

    var displayName: String {
        switch self {
        case let .month(year, month):
            var components = DateComponents()
            components.year = year
            components.month = month
            let date = Calendar.current.date(from: components) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        case let .year(year):
            return "\(year)"
        }
    }

    static func currentMonth(calendar: Calendar = .current) -> WrappedPeriod {
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return .month(year: year, month: month)
    }

    static func previousMonth(calendar: Calendar = .current) -> WrappedPeriod {
        let now = Date()
        let startOfCurrentMonth = calendar.date(
            from: DateComponents(
                year: calendar.component(.year, from: now),
                month: calendar.component(.month, from: now),
                day: 1
            )
        )!
        let startOfPrevMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth)!
        let year = calendar.component(.year, from: startOfPrevMonth)
        let month = calendar.component(.month, from: startOfPrevMonth)
        return .month(year: year, month: month)
    }

    static func currentYear(calendar: Calendar = .current) -> WrappedPeriod {
        let year = calendar.component(.year, from: Date())
        return .year(year)
    }
}

// MARK: - Entry types

nonisolated struct TopTrackEntry: Sendable, Identifiable {
    let rank: Int
    let trackId: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let totalSecondsListened: TimeInterval
    let playCount: Int

    var id: String { trackId }
}

nonisolated struct TopAlbumEntry: Sendable, Identifiable {
    let rank: Int
    let albumId: String
    let title: String
    let artistName: String
    let totalSecondsListened: TimeInterval
    let playCount: Int
    let uniqueTracks: Int

    var id: String { albumId }
}

nonisolated struct TopArtistEntry: Sendable, Identifiable {
    let rank: Int
    let artistId: String
    let name: String
    let totalSecondsListened: TimeInterval
    let playCount: Int
    let uniqueTracks: Int

    var id: String { artistId }
}

// MARK: - WrappedData

nonisolated struct WrappedData: Sendable {
    let period: WrappedPeriod
    let serverId: String
    let generatedAt: Date

    let totalSecondsListened: TimeInterval
    let totalTracksPlayed: Int
    let totalUniqueTracks: Int
    let totalUniqueArtists: Int
    let totalUniqueAlbums: Int

    let topTracks: [TopTrackEntry]
    let topAlbums: [TopAlbumEntry]
    let topArtists: [TopArtistEntry]

    let dominantGenre: String?
    let streakDays: Int

    let firstTrackOfPeriod: TopTrackEntry?
    let lastTrackOfPeriod: TopTrackEntry?
}
