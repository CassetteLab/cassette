// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// Lightweight synchronous store for user-configured external release providers.
/// Persists to UserDefaults as JSON. Not an actor — all callers are on MainActor
/// (SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor applies module-wide).
final class ExternalProvidersStore {
    private static let defaultsKey = "app.cassette.integrations.external-providers"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ExternalReleaseProvider] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([ExternalReleaseProvider].self, from: data)) ?? []
    }

    func save(_ providers: [ExternalReleaseProvider]) {
        guard let data = try? JSONEncoder().encode(providers) else {
            Logger.integrations.error("ExternalProvidersStore: JSON encoding failed")
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func add(_ provider: ExternalReleaseProvider) {
        var current = load()
        current.append(provider)
        save(current)
    }

    func remove(id: UUID) {
        var current = load()
        current.removeAll { $0.id == id }
        save(current)
    }

    func update(_ provider: ExternalReleaseProvider) {
        var current = load()
        if let idx = current.firstIndex(where: { $0.id == provider.id }) {
            current[idx] = provider
        }
        save(current)
    }
}
