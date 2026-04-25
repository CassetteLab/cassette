// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

@MainActor
final class FavoritesService: FavoritesServiceProtocol {
    private let libraryService: any LibraryServiceProtocol
    private let serverState: ServerState
    private let modelContext: ModelContext

    init(libraryService: any LibraryServiceProtocol, serverState: ServerState, modelContainer: ModelContainer) {
        self.libraryService = libraryService
        self.serverState = serverState
        self.modelContext = modelContainer.mainContext
    }

    // MARK: - Query

    func isFavorite(itemType: FavoriteType, itemId: String) -> Bool {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<FavoriteRecord>(
            predicate: #Predicate<FavoriteRecord> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Star

    func star(itemType: FavoriteType, itemId: String) async throws {
        guard let serverId = serverState.activeServer?.id else { return }

        let record = FavoriteRecord(itemType: itemType, itemId: itemId, starredDate: Date(), serverId: serverId)
        modelContext.insert(record)
        try? modelContext.save()

        do {
            switch itemType {
            case .song:   try await libraryService.star(songIds: [itemId], albumIds: [], artistIds: [])
            case .album:  try await libraryService.star(songIds: [], albumIds: [itemId], artistIds: [])
            case .artist: try await libraryService.star(songIds: [], albumIds: [], artistIds: [itemId])
            }
            Logger.favorites.info("Starred \(itemType.rawValue) \(itemId)")
        } catch {
            modelContext.delete(record)
            try? modelContext.save()
            throw error
        }
    }

    // MARK: - Unstar

    func unstar(itemType: FavoriteType, itemId: String) async throws {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<FavoriteRecord>(
            predicate: #Predicate<FavoriteRecord> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }

        let capturedServerId = record.serverId
        let capturedDate = record.starredDate
        modelContext.delete(record)
        try? modelContext.save()

        do {
            switch itemType {
            case .song:   try await libraryService.unstar(songIds: [itemId], albumIds: [], artistIds: [])
            case .album:  try await libraryService.unstar(songIds: [], albumIds: [itemId], artistIds: [])
            case .artist: try await libraryService.unstar(songIds: [], albumIds: [], artistIds: [itemId])
            }
            Logger.favorites.info("Unstarred \(itemType.rawValue) \(itemId)")
        } catch {
            let restored = FavoriteRecord(itemType: itemType, itemId: itemId, starredDate: capturedDate, serverId: capturedServerId)
            modelContext.insert(restored)
            try? modelContext.save()
            throw error
        }
    }

    // MARK: - Sync

    func syncFromServer() async throws {
        guard let serverId = serverState.activeServer?.id else { return }

        let starred = try await libraryService.getStarred2()

        let descriptor = FetchDescriptor<FavoriteRecord>(
            predicate: #Predicate<FavoriteRecord> { $0.serverId == serverId }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingIds = Set(existing.map(\.id))

        var newIds = Set<String>()
        var added = 0
        var unchanged = 0

        func upsert(type: FavoriteType, itemId: String) {
            let compositeId = "\(type.rawValue):\(itemId)"
            newIds.insert(compositeId)
            if existingIds.contains(compositeId) {
                unchanged += 1
            } else {
                modelContext.insert(FavoriteRecord(itemType: type, itemId: itemId, starredDate: Date(), serverId: serverId))
                added += 1
            }
        }

        for song in starred.song ?? []     { upsert(type: .song,   itemId: song.id) }
        for album in starred.album ?? []   { upsert(type: .album,  itemId: album.id) }
        for artist in starred.artist ?? [] { upsert(type: .artist, itemId: artist.id) }

        let toRemove = existing.filter { !newIds.contains($0.id) }
        toRemove.forEach { modelContext.delete($0) }

        try? modelContext.save()
        Logger.favorites.info("Favorites synced: \(added) added, \(toRemove.count) removed, \(unchanged) unchanged")
    }
}
