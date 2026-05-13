// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

/// Maintains four algorithm-driven server playlists and their local SwiftData mirror.
///
/// All SwiftData access uses ephemeral ModelContext instances (never stored).
/// PersistentModel instances never leave this actor — callers receive ThemePlaylistDTO.
actor ThemePlaylistService {
    static let namePrefix = "Cassette — "
    private static let trackLimit = 50

    private let modelContainer: ModelContainer
    private let serverService: any ServerServiceProtocol
    private var cachedClient: SwiftSonicClient?
    private var cachedServerId: UUID?

    init(
        modelContainer: ModelContainer,
        serverService: any ServerServiceProtocol,
        statsService: StatsService
    ) {
        self.modelContainer = modelContainer
        self.serverService = serverService
    }

    // MARK: - Public API

    /// Returns the last-synced DTOs from SwiftData. Never blocks on network.
    func loadCached(serverId: String) async -> [ThemePlaylistDTO] {
        let context = ModelContext(modelContainer)
        let sid = serverId
        let descriptor = FetchDescriptor<ThemePlaylistRecord>(
            predicate: #Predicate { $0.serverId == sid }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { record -> ThemePlaylistDTO? in
            guard let type = record.type else { return nil }
            return ThemePlaylistDTO(
                serverId: record.serverId,
                type: type,
                playlistId: record.playlistId,
                title: record.title,
                trackIds: record.trackIds,
                lastSyncedAt: record.lastSyncedAt
            )
        }
    }

    /// Computes all four themed playlists, pushes them to the server, and persists results.
    func sync(serverId: String) async throws {
        let c = try await client()
        for type in ThemePlaylistType.allCases {
            let trackIds = computeTrackIds(for: type, serverId: serverId)
            guard !trackIds.isEmpty else {
                Logger.themePlaylist.debug("[THEME-SYNC] skip type=\(type.rawValue, privacy: .public) — no tracks")
                continue
            }
            let pid = try await getOrCreateServerPlaylist(for: type, serverId: serverId, client: c)
            _ = try await c.createPlaylist(name: nil, playlistId: pid, songIds: trackIds)
            try await c.updatePlaylist(id: pid, comment: type.description)
            upsert(serverId: serverId, type: type, playlistId: pid,
                   title: Self.namePrefix + type.displayName, trackIds: trackIds)
            Logger.themePlaylist.info("[THEME-SYNC] synced type=\(type.rawValue, privacy: .public) tracks=\(trackIds.count, privacy: .public) pid=\(pid, privacy: .public)")
        }
    }

    // MARK: - Algorithms

    private func computeTrackIds(for type: ThemePlaylistType, serverId: String) -> [String] {
        switch type {
        case .mostPlayedMonth:    mostPlayedMonthIds(serverId: serverId)
        case .hiddenGems:         hiddenGemsIds(serverId: serverId)
        case .forgottenFavorites: forgottenFavoritesIds(serverId: serverId)
        case .recentDiscoveries:  recentDiscoveriesIds(serverId: serverId)
        }
    }

    private func mostPlayedMonthIds(serverId: String) -> [String] {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        let events = fetchEvents(serverId: serverId, from: start, to: end)
        var counts: [String: Int] = [:]
        for e in events { counts[e.trackId, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(Self.trackLimit).map(\.key)
    }

    private func hiddenGemsIds(serverId: String) -> [String] {
        let events = fetchEvents(serverId: serverId)
        var counts: [String: Int] = [:]
        var completed: [String: Bool] = [:]
        for e in events {
            counts[e.trackId, default: 0] += 1
            if e.wasCompleted { completed[e.trackId] = true }
        }
        return counts
            .filter { completed[$0.key] == true && $0.value < 5 }
            .sorted { $0.value > $1.value }
            .prefix(Self.trackLimit)
            .map(\.key)
    }

    private func forgottenFavoritesIds(serverId: String) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let events = fetchEvents(serverId: serverId)
        var counts: [String: Int] = [:]
        var lastPlayed: [String: Date] = [:]
        for e in events {
            counts[e.trackId, default: 0] += 1
            if lastPlayed[e.trackId].map({ e.timestamp > $0 }) ?? true {
                lastPlayed[e.trackId] = e.timestamp
            }
        }
        return counts
            .filter { $0.value >= 3 && (lastPlayed[$0.key] ?? .distantFuture) < cutoff }
            .sorted { $0.value > $1.value }
            .prefix(Self.trackLimit)
            .map(\.key)
    }

    private func recentDiscoveriesIds(serverId: String) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let events = fetchEvents(serverId: serverId)
        var firstPlayed: [String: Date] = [:]
        for e in events {
            if firstPlayed[e.trackId].map({ e.timestamp < $0 }) ?? true {
                firstPlayed[e.trackId] = e.timestamp
            }
        }
        return firstPlayed
            .filter { $0.value >= cutoff }
            .sorted { $0.value > $1.value }
            .prefix(Self.trackLimit)
            .map(\.key)
    }

    // MARK: - SwiftData helpers

    private func fetchEvents(serverId: String, from: Date? = nil, to: Date? = nil) -> [PlaybackEvent] {
        let context = ModelContext(modelContainer)
        let sid = serverId
        let start = from ?? .distantPast
        let end = to ?? .distantFuture
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func upsert(serverId: String, type: ThemePlaylistType, playlistId: String, title: String, trackIds: [String]) {
        let context = ModelContext(modelContainer)
        let sid = serverId
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<ThemePlaylistRecord>(
            predicate: #Predicate { $0.serverId == sid && $0.typeRaw == typeRaw }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.playlistId = playlistId
            existing.title = title
            existing.trackIds = trackIds
            existing.trackCount = trackIds.count
            existing.lastSyncedAt = Date()
        } else {
            context.insert(ThemePlaylistRecord(serverId: serverId, type: type, playlistId: playlistId, title: title, trackIds: trackIds))
        }
        try? context.save()
    }

    // MARK: - Server playlist management

    private func getOrCreateServerPlaylist(for type: ThemePlaylistType, serverId: String, client: SwiftSonicClient) async throws -> String {
        let context = ModelContext(modelContainer)
        let sid = serverId
        let typeRaw = type.rawValue
        let localDescriptor = FetchDescriptor<ThemePlaylistRecord>(
            predicate: #Predicate { $0.serverId == sid && $0.typeRaw == typeRaw }
        )
        if let record = (try? context.fetch(localDescriptor))?.first {
            return record.playlistId
        }

        let name = Self.namePrefix + type.displayName
        let existing = try await client.getPlaylists()
        if let found = existing.first(where: { $0.name == name }) {
            Logger.themePlaylist.info("[THEME-SYNC] found existing '\(name, privacy: .public)' id=\(found.id, privacy: .public)")
            return found.id
        }

        let created = try await client.createPlaylist(name: name)
        Logger.themePlaylist.info("[THEME-SYNC] created '\(name, privacy: .public)' id=\(created.id, privacy: .public)")
        return created.id
    }

    // MARK: - Client

    private func client() async throws -> SwiftSonicClient {
        let activeId = await MainActor.run { serverService.state.activeServer?.id }
        if let cached = cachedClient, cachedServerId == activeId, activeId != nil {
            return cached
        }
        let fresh = try await serverService.makeSwiftSonicClient()
        cachedClient = fresh
        cachedServerId = activeId
        return fresh
    }
}
