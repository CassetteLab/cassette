import Testing
import Foundation
import SwiftData
@testable import Cassette

// MARK: - Mock

final actor MockKeychain: KeychainServiceProtocol {
    private var storage: [String: Data] = [:]
    private var failOnStore = false

    func setShouldFailOnStore(_ value: Bool) { failOnStore = value }

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        if failOnStore { throw CassetteError.keychainWriteFailed(-1) }
        storage[key] = try JSONEncoder().encode(value)
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func delete(forKey key: String) async throws {
        storage.removeValue(forKey: key)
    }
}

// MARK: - Suite

@Suite("ServerService")
@MainActor
struct ServerServiceTests {

    private func makeService(keychain: MockKeychain = MockKeychain()) throws -> (ServerService, ServerState) {
        let container = try ModelContainer.cassette(inMemory: true)
        let state = ServerState()
        let service = ServerService(state: state, keychain: keychain, modelContainer: container)
        return (service, state)
    }

    // MARK: addServer

    @Test func addServer_firstServer_becomesActive() async throws {
        let (service, state) = try makeService()

        try await service.addServer(
            displayName: "My Server", baseURL: "https://music.example.com",
            username: "admin", password: "secret", customHeaders: [:]
        )

        #expect(state.servers.count == 1)
        #expect(state.activeServer?.username == "admin")
        #expect(state.activeServer?.displayName == "My Server")
    }

    @Test func addServer_secondServer_doesNotBecomeActive() async throws {
        let (service, state) = try makeService()

        try await service.addServer(
            displayName: "S1", baseURL: "https://s1.example.com",
            username: "user1", password: "pass", customHeaders: [:]
        )
        try await service.addServer(
            displayName: "S2", baseURL: "https://s2.example.com",
            username: "user2", password: "pass", customHeaders: [:]
        )

        #expect(state.servers.count == 2)
        #expect(state.activeServer?.username == "user1")
    }

    @Test func addServer_invalidHeaderName_throwsInvalidHeaderName() async throws {
        let (service, _) = try makeService()

        await #expect(throws: CassetteError.self) {
            try await service.addServer(
                displayName: "S", baseURL: "https://s.example.com",
                username: "u", password: "p",
                customHeaders: ["Bad Header": "value"]
            )
        }
    }

    @Test func addServer_keychainFailure_stateUnchanged() async throws {
        let keychain = MockKeychain()
        await keychain.setShouldFailOnStore(true)
        let (service, state) = try makeService(keychain: keychain)

        try? await service.addServer(
            displayName: "S", baseURL: "https://s.example.com",
            username: "u", password: "p", customHeaders: [:]
        )

        #expect(state.servers.isEmpty)
        #expect(state.activeServer == nil)
    }

    // MARK: removeServer

    @Test func removeServer_removesFromStateAndClearsActive() async throws {
        let (service, state) = try makeService()

        try await service.addServer(
            displayName: "S", baseURL: "https://s.example.com",
            username: "u", password: "p", customHeaders: [:]
        )
        let id = try #require(state.servers.first).id
        try await service.removeServer(id: id)

        #expect(state.servers.isEmpty)
        #expect(state.activeServer == nil)
        #expect(state.isConnected == false)
    }

    @Test func removeServer_unknownId_throwsServerNotFound() async throws {
        let (service, _) = try makeService()

        await #expect(throws: CassetteError.self) {
            try await service.removeServer(id: UUID())
        }
    }

    // MARK: setActiveServer

    @Test func setActiveServer_switchesActiveServer() async throws {
        let (service, state) = try makeService()

        try await service.addServer(
            displayName: "S1", baseURL: "https://s1.example.com",
            username: "user1", password: "pass", customHeaders: [:]
        )
        try await service.addServer(
            displayName: "S2", baseURL: "https://s2.example.com",
            username: "user2", password: "pass", customHeaders: [:]
        )

        let s2Id = try #require(state.servers.first(where: { $0.username == "user2" })).id
        try await service.setActiveServer(id: s2Id)

        #expect(state.activeServer?.username == "user2")
        #expect(state.isConnected == false)
    }

    @Test func setActiveServer_unknownId_throwsServerNotFound() async throws {
        let (service, _) = try makeService()

        await #expect(throws: CassetteError.self) {
            try await service.setActiveServer(id: UUID())
        }
    }

    // MARK: loadPersistedState

    @Test func loadPersistedState_restoresServersAndActiveServer() async throws {
        let keychain = MockKeychain()
        let container = try ModelContainer.cassette(inMemory: true)

        let state1 = ServerState()
        let service1 = ServerService(state: state1, keychain: keychain, modelContainer: container)
        try await service1.addServer(
            displayName: "Persisted", baseURL: "https://s.example.com",
            username: "user", password: "pass", customHeaders: [:]
        )

        // Simulate app restart: new service with the same container
        let state2 = ServerState()
        let service2 = ServerService(state: state2, keychain: keychain, modelContainer: container)

        #expect(state2.servers.isEmpty)
        await service2.loadPersistedState()

        #expect(state2.servers.count == 1)
        #expect(state2.activeServer?.username == "user")
        #expect(state2.isLoadingPersistedState == false)
    }
}
