// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

/// Persists and restores playback sessions via SwiftData.
///
/// Called by PlayerService on track changes and every 5 s during active playback,
/// and flushed in full when the app enters background.
@MainActor
final class PlaybackSessionService {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }

    /// Full save — queue + position + current track metadata.
    func save(playerState: PlayerState) {
        let session = fetchOrCreateSession()
        session.update(
            currentIndex: playerState.currentIndex,
            currentPosition: playerState.position,
            queue: playerState.queue,
            currentTrack: playerState.currentTrack
        )
        try? modelContext.save()
        Logger.session.debug("Session saved: track='\(playerState.currentTrack?.title ?? "nil")', pos=\(playerState.position, format: .fixed(precision: 1))s, queue=\(playerState.queue.count) tracks")
    }

    /// Lightweight position-only save — called every 5 s during active playback.
    func savePosition(_ position: TimeInterval) {
        guard let session = fetchSession() else { return }
        session.currentPosition = position
        session.lastUpdated = Date()
        try? modelContext.save()
    }

    /// Returns the persisted session, or nil if none exists.
    func load() -> PlaybackSession? {
        let session = fetchSession()
        if let session {
            Logger.session.info("Session loaded: track='\(session.currentTrackTitle ?? "nil")', pos=\(session.currentPosition, format: .fixed(precision: 1))s, queue=\(session.decodedQueue().count) tracks")
        } else {
            Logger.session.info("No persisted session found")
        }
        return session
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
