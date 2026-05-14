// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("ExternalProvidersStore")
struct ExternalProvidersStoreTests {

    private func makeStore() -> ExternalProvidersStore {
        ExternalProvidersStore(defaults: UserDefaults(suiteName: "test.providers.\(UUID().uuidString)")!)
    }

    private var sampleProvider: ExternalReleaseProvider {
        ExternalReleaseProvider(id: UUID(), name: "Bandcamp", urlTemplate: "https://bandcamp.com/search?q=%s")
    }

    @Test("load returns empty array when key is not present")
    func emptyByDefault() {
        let store = makeStore()
        #expect(store.load().isEmpty)
    }

    @Test("save and load roundtrip preserves all fields")
    func saveLoadRoundtrip() {
        let store = makeStore()
        let p = sampleProvider
        store.save([p])
        let loaded = store.load()
        #expect(loaded == [p])
    }

    @Test("add appends provider and persists")
    func addAppends() {
        let store = makeStore()
        let p1 = sampleProvider
        let p2 = ExternalReleaseProvider(name: "Beatport", urlTemplate: "https://beatport.com/search?q=%s")
        store.add(p1)
        store.add(p2)
        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded[0] == p1)
        #expect(loaded[1] == p2)
    }

    @Test("remove deletes provider by id")
    func removeById() {
        let store = makeStore()
        let p = sampleProvider
        store.add(p)
        store.remove(id: p.id)
        #expect(store.load().isEmpty)
    }

    @Test("remove with unknown id leaves providers unchanged")
    func removeUnknownIDIsNoOp() {
        let store = makeStore()
        store.add(sampleProvider)
        store.remove(id: UUID())
        #expect(store.load().count == 1)
    }

    @Test("update replaces provider by id, preserving others")
    func updateReplacesById() {
        let store = makeStore()
        let p = sampleProvider
        store.add(p)
        var updated = p
        updated.name = "Bandcamp Pro"
        store.update(updated)
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == p.id)
        #expect(loaded[0].name == "Bandcamp Pro")
    }

    @Test("corrupt JSON in UserDefaults returns empty gracefully without crashing")
    func corruptJSONGraceful() {
        let defaults = UserDefaults(suiteName: "test.corrupt.\(UUID().uuidString)")!
        defaults.set(Data("not-valid-json".utf8), forKey: "app.cassette.integrations.external-providers")
        let store = ExternalProvidersStore(defaults: defaults)
        #expect(store.load().isEmpty)
    }
}
