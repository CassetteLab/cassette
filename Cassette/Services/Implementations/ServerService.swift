import Foundation
import SwiftData
import SwiftSonic
import OSLog

actor ServerService: ServerServiceProtocol {
    nonisolated let state: ServerState

    private let keychain: any KeychainServiceProtocol
    private let modelContainer: ModelContainer

    init(state: ServerState, keychain: any KeychainServiceProtocol, modelContainer: ModelContainer) {
        self.state = state
        self.keychain = keychain
        self.modelContainer = modelContainer
    }

    func addServer(
        displayName: String,
        baseURL: String,
        username: String,
        password: String,
        customHeaders: [String: String]
    ) async throws {
        try validateHeaders(customHeaders)

        let configId = UUID()
        let creds = ServerCredentials(password: password, customHeaders: customHeaders)
        let credKey = ServerCredentials.keychainKey(for: configId)

        // Keychain first: if SwiftData save fails below, we can roll back with a single delete.
        try await keychain.store(creds, forKey: credKey)

        do {
            try await MainActor.run {
                let context = ModelContext(modelContainer)
                let existingCount = (try? context.fetchCount(FetchDescriptor<ServerConfig>())) ?? 0
                let isFirst = existingCount == 0
                let config = ServerConfig(
                    id: configId,
                    displayName: displayName,
                    baseURL: baseURL,
                    username: username,
                    isActive: isFirst
                )
                context.insert(config)
                try context.save()
                let snapshot = ServerSnapshot(from: config)
                state.servers.append(snapshot)
                if isFirst {
                    state.activeServer = snapshot
                }
            }
        } catch {
            try? await keychain.delete(forKey: credKey)
            throw error
        }
    }

    func removeServer(id: UUID) async throws {
        // Atomic: delete from SwiftData first, then Keychain.
        // Best-effort rollback if Keychain deletion fails after SwiftData deletion.
        // TODO: implement in Étape 2
    }

    func setActiveServer(id: UUID) async throws {
        // TODO: implement in Étape 2
    }

    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {
        try validateHeaders(headers)
        // TODO: implement in Settings (Étape 7)
    }

    func loadPersistedState() async {
        // TODO(Étape 2-5): fetch ServerConfig records from SwiftData, retrieve credentials from
        // Keychain, and restore state.servers + state.activeServer.
        // ModelContext must always be created and used on MainActor — access via:
        //   let context = await MainActor.run { ModelContext(modelContainer) }
        await MainActor.run { state.isLoadingPersistedState = false }
    }

    func testConnection() async throws {
        let client = try await makeSwiftSonicClient()
        try await client.ping()
    }

    func makeSwiftSonicClient() async throws -> SwiftSonicClient {
        let snapshot = await MainActor.run { state.activeServer }
        guard let snapshot else { throw CassetteError.serverNotConfigured }

        let creds = try await keychain.retrieve(
            ServerCredentials.self,
            forKey: ServerCredentials.keychainKey(for: snapshot.id)
        )
        guard let creds else { throw CassetteError.serverNotConfigured }

        guard let url = URL(string: snapshot.baseURL) else {
            throw CassetteError.invalidServerURL(snapshot.baseURL)
        }

        let transport = CustomHeadersTransport(headers: creds.customHeaders)
        return SwiftSonicClient(
            serverURL: url,
            username: snapshot.username,
            password: creds.password,
            transport: transport
        )
    }

    func activeCredentials() async throws -> ServerCredentials {
        let snapshot = await MainActor.run { state.activeServer }
        guard let snapshot else { throw CassetteError.serverNotConfigured }

        guard let creds = try await keychain.retrieve(
            ServerCredentials.self,
            forKey: ServerCredentials.keychainKey(for: snapshot.id)
        ) else { throw CassetteError.serverNotConfigured }

        return creds
    }

    // MARK: - Private

    private func validateHeaders(_ headers: [String: String]) throws {
        for (key, value) in headers {
            guard !value.contains("\r"), !value.contains("\n") else {
                throw CassetteError.invalidHeaderValue(key: key)
            }
        }
    }
}
