// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

/// Reads/writes the per-device `PlaylistCoverChoice` records, keyed by `(playlistId, serverId)`. Backed by
/// the container's `mainContext` (so saves are observed by `@Query`, matching the app's PinService pattern)
/// — hence `@MainActor`. Cross-platform.
@MainActor
struct PlaylistCoverStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private static func match(_ playlistId: String, _ serverId: UUID) -> Predicate<PlaylistCoverChoice> {
        #Predicate<PlaylistCoverChoice> { $0.playlistId == playlistId && $0.serverId == serverId }
    }

    /// The stored gradient choice for this playlist, or `nil` if none / the stored form no longer exists.
    func choice(playlistId: String, serverId: UUID) -> PlaylistCoverChoice? {
        var descriptor = FetchDescriptor(predicate: Self.match(playlistId, serverId))
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    /// Upserts the gradient choice. A SYSTEM default (`isUserPicked == false`) never overwrites an existing
    /// USER pick — so an explicit choice is preserved when e.g. a neutral default is later (re)applied.
    func save(_ spec: PlaylistGradientSpec, playlistId: String, serverId: UUID, isUserPicked: Bool) {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor(predicate: Self.match(playlistId, serverId))
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        if let existing {
            if existing.isUserPicked && !isUserPicked { return }
            existing.shapeRawValue = spec.shape.rawValue
            existing.red = spec.red
            existing.green = spec.green
            existing.blue = spec.blue
            existing.isUserPicked = isUserPicked
            existing.updatedAt = Date()
        } else {
            context.insert(
                PlaylistCoverChoice(playlistId: playlistId, serverId: serverId, spec: spec, isUserPicked: isUserPicked)
            )
        }
        do {
            try context.save()
        } catch {
            Logger.playlist.warning("PlaylistCoverStore: save failed: \(error)")
        }
    }

    /// Removes the choice for a playlist (orphan cleanup on playlist delete).
    func remove(playlistId: String, serverId: UUID) {
        let context = modelContainer.mainContext
        guard let matches = try? context.fetch(FetchDescriptor(predicate: Self.match(playlistId, serverId))),
              !matches.isEmpty else { return }
        for match in matches { context.delete(match) }
        do {
            try context.save()
        } catch {
            Logger.playlist.warning("PlaylistCoverStore: remove failed: \(error)")
        }
    }
}
