// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

// MARK: - Revalidation decision

/// The verdict of comparing the server's current `Last-Modified` against the one we last saw.
///
/// Pure and side-effect free so the branching is unit-testable without a network. Navidrome sends
/// `Last-Modified` on `getCoverArt` but never answers `304`, so we read the header off a HEAD and
/// decide here rather than relying on HTTP conditional caching.
nonisolated enum CoverRevalidationOutcome: Equatable {
    /// First time we check this cover: adopt the server value as the baseline, keep the image.
    case baseline
    /// Header unchanged — the cover has not changed. Keep the cached image, just reset the timer.
    case unchanged
    /// Header moved — the cover was replaced on the server. Re-fetch the bytes.
    case changed
    /// No usable `Last-Modified` header (server didn't send one). Cannot tell; leave things be.
    case indeterminate

    static func decide(stored: String?, server: String?) -> CoverRevalidationOutcome {
        guard let server, !server.isEmpty else { return .indeterminate }
        guard let stored, !stored.isEmpty else { return .baseline }
        return server == stored ? .unchanged : .changed
    }
}

// MARK: - CoverRevalidationStore

/// Remembers, per cover art id, the `Last-Modified` we last saw and when we last checked — so a
/// cover can be re-verified on a slow cadence rather than trusted forever.
///
/// Navidrome bakes the album's `UpdatedAt` into the cover id, which changes the cache key when the
/// album record changes — but NOT when only the folder image is swapped, and never at all for
/// artist art (whose id carries no version). The only signal that survives all three cases is the
/// `Last-Modified` header. This store is what lets the cache act on it lazily.
///
/// Persisted as one small JSON file. Writes are coalesced because the first warm-up after launch
/// records a baseline for every visible cover at once.
@MainActor
final class CoverRevalidationStore {
    struct Entry: Codable, Equatable {
        var lastModified: String?
        var lastChecked: Date
    }

    /// How long a recorded check is trusted before the cover is re-verified. Cover changes are
    /// rare, so a week keeps network noise negligible while still self-healing within days.
    nonisolated static let defaultTTL: TimeInterval = 7 * 24 * 3600

    private var entries: [String: Entry]
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    nonisolated init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    // MARK: - Queries

    /// Whether `id` should be re-verified: never checked, or checked longer ago than `ttl`.
    func isDue(id: String, now: Date = Date(), ttl: TimeInterval = defaultTTL) -> Bool {
        guard let entry = entries[id] else { return true }
        return now.timeIntervalSince(entry.lastChecked) >= ttl
    }

    func lastModified(for id: String) -> String? { entries[id]?.lastModified }

    // MARK: - Mutations

    /// Records the outcome of a check (or a fresh fetch): stores the server's `Last-Modified` and
    /// resets the timer. Passing `nil` for `lastModified` keeps whatever was there.
    func record(id: String, lastModified: String?, checkedAt: Date = Date()) {
        let resolved = lastModified ?? entries[id]?.lastModified
        entries[id] = Entry(lastModified: resolved, lastChecked: checkedAt)
        scheduleSave()
    }

    /// Forgets everything — used by the version-bump cache wipe so stale metadata never outlives the
    /// images it described.
    func removeAll() {
        entries.removeAll()
        pendingSave?.cancel()
        pendingSave = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Writes any pending changes to disk immediately, bypassing the debounce. Tests use this to
    /// avoid depending on the coalescing timer.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        saveNow()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.saveNow()
            self?.pendingSave = nil
        }
    }

    private func saveNow() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.artworkCache.warning("[REVAL] could not persist revalidation store: \(error, privacy: .public)")
        }
    }

    nonisolated private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.cassette", isDirectory: true)
        return base.appendingPathComponent("coverart-revalidation.json")
    }
}
