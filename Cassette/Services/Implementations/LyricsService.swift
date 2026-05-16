// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

/// Fetches and caches structured lyrics for the active server.
///
/// All persistence uses a private ModelContext created per operation.
/// No UIKit or SwiftUI imports — this actor is platform-agnostic.
actor LyricsService {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer

    init(serverService: any ServerServiceProtocol, modelContainer: ModelContainer) {
        self.serverService = serverService
        self.modelContainer = modelContainer
    }

    // MARK: - Fetch

    /// Returns lyrics for a song. Checks cache first; falls back to network on miss.
    /// On network error, returns cached data if available (offline mode).
    func fetchLyrics(forSongId songId: String, serverId: UUID) async throws -> LyricsList {
        if let cached = await cachedLyrics(songId: songId, serverId: serverId) {
            Logger.lyrics.debug("Cache hit — songId=\(songId, privacy: .public)")
            return cached
        }

        let client = try await serverService.makeSwiftSonicClient()
        let capabilities = try await client.loadCapabilities()
        guard capabilities.supports(.songLyrics) else {
            throw LyricsError.notSupportedByServer
        }

        do {
            let list = try await client.getLyricsBySongId(id: songId)
            guard !list.structuredLyrics.isEmpty else {
                throw LyricsError.notFound
            }
            await persistLyrics(list, songId: songId, serverId: serverId)
            return list
        } catch let error as LyricsError {
            throw error
        } catch {
            if let cached = await cachedLyrics(songId: songId, serverId: serverId) {
                Logger.lyrics.info("Network error, returning cached lyrics — songId=\(songId, privacy: .public)")
                return cached
            }
            Logger.lyrics.error("Lyrics fetch failed — songId=\(songId, privacy: .public): \(error, privacy: .public)")
            throw LyricsError.networkError(underlying: error.localizedDescription)
        }
    }

    // MARK: - Language Selection

    /// Picks the best StructuredLyrics set for the given locale and optional user preference.
    ///
    /// Priority:
    /// 1. User-selected `preferred` language — synced variant if available, else unsynced.
    /// 2. System locale language — synced variant if available, else unsynced.
    /// 3. Any synced set, then first available.
    ///
    /// "xxx" is normalised to "und" per OpenSubsonic spec (both mean unspecified language).
    nonisolated func selectBestLanguage(
        from list: LyricsList,
        locale: Locale = .current,
        preferred: String? = nil
    ) -> StructuredLyrics? {
        let entries = list.structuredLyrics
        guard !entries.isEmpty else { return nil }

        func normalized(_ lang: String?) -> String? {
            lang == "xxx" ? "und" : lang
        }

        func best(among candidates: [StructuredLyrics]) -> StructuredLyrics? {
            candidates.first(where: { $0.synced }) ?? candidates.first
        }

        if let preferred {
            let matching = entries.filter { normalized($0.lang) == preferred }
            if let hit = best(among: matching) { return hit }
        }

        let langCode = locale.language.languageCode?.identifier ?? ""
        if !langCode.isEmpty {
            let matching = entries.filter { normalized($0.lang) == langCode }
            if let hit = best(among: matching) { return hit }
        }

        return entries.first(where: { $0.synced }) ?? entries.first
    }

    // MARK: - Private cache

    private func cachedLyrics(songId: String, serverId: UUID) async -> LyricsList? {
        let key = "\(serverId.uuidString):\(songId)"
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        do {
            let payload = entry.jsonPayload
            return try await MainActor.run { try JSONDecoder().decode(LyricsList.self, from: payload) }
        } catch {
            Logger.lyrics.error("Cache corrupted — key=\(key, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func persistLyrics(_ list: LyricsList, songId: String, serverId: UUID) async {
        let data = try? await MainActor.run { try JSONEncoder().encode(list) }
        guard let data else { return }
        let key = "\(serverId.uuidString):\(songId)"
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
        }
        context.insert(CachedLyrics(songId: songId, serverId: serverId, jsonPayload: data))
        try? context.save()
        Logger.lyrics.debug("Persisted lyrics — songId=\(songId, privacy: .public)")
    }
}
