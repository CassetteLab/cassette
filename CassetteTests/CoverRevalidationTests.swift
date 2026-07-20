// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("Cover art revalidation — decision")
struct CoverRevalidationOutcomeTests {

    @Test("no stored value yet is a baseline, not a change")
    func firstObservationIsBaseline() {
        // Adopting the server value on first sight must NOT trigger a refetch — the cached image is
        // presumed current; we're only recording what to compare against next time.
        #expect(CoverRevalidationOutcome.decide(stored: nil, server: "Wed, 26 Mar 2025 22:26:49 GMT") == .baseline)
        #expect(CoverRevalidationOutcome.decide(stored: "", server: "Wed, 26 Mar 2025 22:26:49 GMT") == .baseline)
    }

    @Test("same header means the cover is unchanged")
    func identicalHeaderIsUnchanged() {
        let lm = "Wed, 26 Mar 2025 22:26:49 GMT"
        #expect(CoverRevalidationOutcome.decide(stored: lm, server: lm) == .unchanged)
    }

    @Test("a moved header means the cover changed")
    func movedHeaderIsChanged() {
        #expect(CoverRevalidationOutcome.decide(
            stored: "Wed, 26 Mar 2025 22:26:49 GMT",
            server: "Wed, 09 Jul 2025 05:05:24 GMT") == .changed)
    }

    @Test("a missing server header is indeterminate — never a false change")
    func noServerHeaderIsIndeterminate() {
        // A server that doesn't send Last-Modified must not cause a pointless refetch every check.
        #expect(CoverRevalidationOutcome.decide(stored: "Wed, 26 Mar 2025 22:26:49 GMT", server: nil) == .indeterminate)
        #expect(CoverRevalidationOutcome.decide(stored: nil, server: nil) == .indeterminate)
        #expect(CoverRevalidationOutcome.decide(stored: "x", server: "") == .indeterminate)
    }
}

@Suite("Cover art revalidation — store")
@MainActor
struct CoverRevalidationStoreTests {

    private func tempStore() -> (CoverRevalidationStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reval-\(UUID().uuidString).json")
        return (CoverRevalidationStore(fileURL: url), url)
    }

    private let ttl: TimeInterval = 7 * 24 * 3600

    @Test("an unknown cover is always due")
    func unknownIsDue() {
        let (store, _) = tempStore()
        #expect(store.isDue(id: "al-x", now: Date(), ttl: ttl))
    }

    @Test("a just-checked cover is not due")
    func recentlyCheckedNotDue() {
        let (store, _) = tempStore()
        let now = Date()
        store.record(id: "al-x", lastModified: "lm", checkedAt: now)
        #expect(!store.isDue(id: "al-x", now: now, ttl: ttl))
        #expect(!store.isDue(id: "al-x", now: now.addingTimeInterval(ttl - 60), ttl: ttl))
    }

    @Test("a cover checked longer ago than the TTL is due again")
    func staleCheckIsDue() {
        let (store, _) = tempStore()
        let checked = Date()
        store.record(id: "al-x", lastModified: "lm", checkedAt: checked)
        #expect(store.isDue(id: "al-x", now: checked.addingTimeInterval(ttl + 1), ttl: ttl))
    }

    @Test("recording nil last-modified keeps the previous value")
    func recordNilPreservesLastModified() {
        let (store, _) = tempStore()
        store.record(id: "al-x", lastModified: "original", checkedAt: Date())
        store.record(id: "al-x", lastModified: nil, checkedAt: Date())
        #expect(store.lastModified(for: "al-x") == "original")
    }

    @Test("entries survive a reload from disk")
    func persistsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reval-persist-\(UUID().uuidString).json")
        let first = CoverRevalidationStore(fileURL: url)
        let checked = Date(timeIntervalSince1970: 1_000_000)
        first.record(id: "al-persist", lastModified: "kept", checkedAt: checked)
        first.flush()   // write now instead of waiting on the debounce

        let second = CoverRevalidationStore(fileURL: url)
        #expect(second.lastModified(for: "al-persist") == "kept")
        #expect(!second.isDue(id: "al-persist", now: checked, ttl: ttl))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("removeAll forgets everything and deletes the file")
    func removeAllClears() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reval-clear-\(UUID().uuidString).json")
        let store = CoverRevalidationStore(fileURL: url)
        store.record(id: "al-x", lastModified: "lm", checkedAt: Date())
        store.flush()
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.removeAll()
        #expect(store.lastModified(for: "al-x") == nil)
        #expect(store.isDue(id: "al-x", now: Date(), ttl: ttl))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
