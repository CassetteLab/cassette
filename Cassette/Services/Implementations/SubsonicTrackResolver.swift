// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

/// Finds a library track from its metadata, one search at a time.
///
/// The escape hatch for AudioMuse handing back ids the music server cannot match: its results still
/// name the track, so it can be looked up. The choice of tracks remains AudioMuse's — only its
/// identifiers are thrown away.
///
/// Resolutions are cached, hits and misses alike, because the same track routinely turns up in
/// several moods and a miss is just as expensive to establish as a hit.
actor SubsonicTrackResolver {
    private let libraryService: any LibraryServiceProtocol
    private var resolved: [String: String] = [:]
    private var missed: Set<String> = []

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    /// Library id for `descriptor`, or nil when nothing matches confidently.
    func resolve(_ descriptor: TrackDescriptor) async -> String? {
        let key = descriptor.cacheKey
        if let hit = resolved[key] { return hit }
        if missed.contains(key) { return nil }

        // Title and artist together, because a bare title returns the whole library's worth of
        // "Intro" and the server ranks better with both.
        let query = [descriptor.title, descriptor.artist].compactMap { $0 }.joined(separator: " ")
        guard let result = try? await libraryService.search(query) else {
            // A transient failure is not a miss — leaving it uncached lets the next run retry.
            return nil
        }

        let candidates = (result.song ?? []).map {
            TrackDescriptor.Candidate(id: $0.id, title: $0.title, artist: $0.artist)
        }
        guard let match = TrackMatcher.bestMatch(for: descriptor, among: candidates) else {
            missed.insert(key)
            return nil
        }
        resolved[key] = match
        return match
    }

    /// Resolves a batch in order, dropping what cannot be found.
    ///
    /// Sequential on purpose. This runs inside the weekly background job where nobody is waiting,
    /// and firing dozens of searches at a self-hosted server at once is the same mistake Instant
    /// Mix already paid for.
    func resolveAll(_ descriptors: [TrackDescriptor]) async -> [String] {
        var ids: [String] = []
        for descriptor in descriptors {
            if let id = await resolve(descriptor) { ids.append(id) }
        }
        return ids
    }
}
