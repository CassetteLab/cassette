// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

/// Persists and restores playback sessions via SwiftData.
///
/// Called by PlayerService on track changes and every 5 s during active playback,
/// and flushed in full when the app enters background.
actor PlaybackSessionService {
    private let modelContainer: ModelContainer
    // Lazy so the context is created on the actor's executor, not the MainActor caller of init.
    private lazy var modelContext: ModelContext = ModelContext(modelContainer)

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Full save — queue + position + current track metadata + repeat mode.
    func save(playerState: SessionPayload) {
        let session = fetchOrCreateSession()
        session.update(
            currentIndex: playerState.currentIndex,
            currentPosition: playerState.currentPosition,
            queue: playerState.queue,
            currentTrack: playerState.currentTrack,
            repeatMode: playerState.repeatMode
        )
        try? modelContext.save()
        Logger.session.debug("Session saved: track='\(playerState.currentTrack?.title ?? "nil", privacy: .private)', pos=\(playerState.currentPosition, format: .fixed(precision: 1), privacy: .public)s, queue=\(playerState.queue.count, privacy: .public) tracks")
    }

    /// Lightweight position-only save — called every 5 s during active playback.
    func savePosition(_ position: TimeInterval) {
        guard let session = fetchSession() else { return }
        session.currentPosition = position
        session.lastUpdated = Date()
        try? modelContext.save()
    }

    /// Extracts and returns restoration data, keeping @Model objects on this actor's context.
    func loadRestoredSession() -> RestoredSession? {
        guard let session = fetchSession() else {
            Logger.session.info("No persisted session found")
            return nil
        }
        let queue = session.decodedQueue()
        guard !queue.isEmpty else {
            Logger.session.info("Persisted session has empty queue — skipping restore")
            return nil
        }
        let safeIndex = min(session.currentIndex, queue.count - 1)
        Logger.session.info("Session loaded: '\(session.currentTrackTitle ?? "nil", privacy: .private)', pos=\(session.currentPosition, format: .fixed(precision: 1), privacy: .public)s, \(queue.count, privacy: .public) tracks")
        return RestoredSession(
            queue: queue,
            currentIndex: safeIndex,
            currentPosition: session.currentPosition,
            currentTrackDuration: session.currentTrackDuration,
            repeatMode: session.decodedRepeatMode()
        )
    }

    func clear() {
        guard let session = fetchSession() else { return }
        modelContext.delete(session)
        try? modelContext.save()
        Logger.session.info("Session cleared")
    }

    private func fetchOrCreateSession() -> PlaybackSession {
        if let existing = fetchSession() { return existing }
        let new = PlaybackSession()
        modelContext.insert(new)
        return new
    }

    private func fetchSession() -> PlaybackSession? {
        let descriptor = FetchDescriptor<PlaybackSession>(
            predicate: #Predicate { $0.id == "current" }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - SessionPayload

nonisolated struct SessionPayload: Sendable {
    let currentIndex: Int
    let currentPosition: TimeInterval
    let queue: [DisplayableSong]
    let currentTrack: DisplayableSong?
    let repeatMode: RepeatMode
}

// MARK: - RestoredSession

/// Value-type snapshot passed to actor-isolated callers — avoids exposing @Model across actor boundary.
nonisolated struct RestoredSession: Sendable {
    let queue: [DisplayableSong]
    let currentIndex: Int
    let currentPosition: TimeInterval
    let currentTrackDuration: TimeInterval
    let repeatMode: RepeatMode
}
