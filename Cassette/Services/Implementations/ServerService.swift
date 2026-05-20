// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import SwiftSonic
import OSLog

actor ServerService: ServerServiceProtocol {
    nonisolated let state: ServerState

    private let keychain: any KeychainServiceProtocol
    private let modelContainer: ModelContainer
    private let cacheService: any CacheServiceProtocol

    init(state: ServerState, keychain: any KeychainServiceProtocol, modelContainer: ModelContainer, cacheService: any CacheServiceProtocol) {
        self.state = state
        self.keychain = keychain
        self.modelContainer = modelContainer
        self.cacheService = cacheService
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
        let credKey = ServerCredentials.keychainKey(for: id)

        try await MainActor.run {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<ServerConfig>(
                predicate: #Predicate { $0.id == id }
            )
            guard let config = try context.fetch(descriptor).first else {
                throw CassetteError.serverNotFound(id: id)
            }
            context.delete(config)
            try context.save()
            state.servers.removeAll { $0.id == id }
            if state.activeServer?.id == id {
                state.activeServer = nil
                state.isConnected = false
            }
        }

        // Best-effort: an orphaned Keychain entry is harmless if this fails.
        try? await keychain.delete(forKey: credKey)
    }

    func setActiveServer(id: UUID) async throws {
        let allServerIds = try await MainActor.run {
            let context = ModelContext(modelContainer)
            let all = try context.fetch(FetchDescriptor<ServerConfig>())
            guard let target = all.first(where: { $0.id == id }) else {
                throw CassetteError.serverNotFound(id: id)
            }
            for config in all { config.isActive = false }
            target.isActive = true
            try context.save()
            state.activeServer = ServerSnapshot(from: target)
            state.isConnected = false
            return all.map(\.id)
        }

        // Best-effort: clear the audio cache for every server that is no longer active.
        let othersToClean = allServerIds.filter { $0 != id }
        guard !othersToClean.isEmpty else {
            Logger.server.debug("No other servers to clean cache for at switch.")
            return
        }
        for serverId in othersToClean {
            await cacheService.clearAllForServer(serverId)
        }
        Logger.server.info("Cleared cache for \(othersToClean.count) non-active server(s) at switch.")
    }

    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {
        try validateHeaders(headers)
        let credKey = ServerCredentials.keychainKey(for: id)
        guard let existing = try await keychain.retrieve(ServerCredentials.self, forKey: credKey) else {
            throw CassetteError.serverNotFound(id: id)
        }
        let updated = ServerCredentials(password: existing.password, customHeaders: headers)
        try await keychain.store(updated, forKey: credKey)
    }

    func updateServer(
        id: UUID,
        displayName: String,
        baseURL: String,
        username: String,
        password: String,
        customHeaders: [String: String]
    ) async throws {
        try validateHeaders(customHeaders)

        let credKey = ServerCredentials.keychainKey(for: id)
        let creds = ServerCredentials(password: password, customHeaders: customHeaders)

        // Keychain first — mirrors addServer rollback strategy.
        try await keychain.store(creds, forKey: credKey)

        do {
            try await MainActor.run {
                let context = ModelContext(modelContainer)
                let descriptor = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
                guard let config = try context.fetch(descriptor).first else {
                    throw CassetteError.serverNotFound(id: id)
                }
                config.displayName = displayName
                config.baseURL = baseURL
                config.username = username
                try context.save()
                let snapshot = ServerSnapshot(from: config)
                if let idx = state.servers.firstIndex(where: { $0.id == id }) {
                    state.servers[idx] = snapshot
                }
                if state.activeServer?.id == id {
                    state.activeServer = snapshot
                }
            }
        } catch {
            throw error
        }
    }

    func loadPersistedState() async {
        do {
            let serverIDs = try await MainActor.run {
                let context = ModelContext(modelContainer)
                let configs = try context.fetch(FetchDescriptor<ServerConfig>())
                state.servers = configs.map { ServerSnapshot(from: $0) }
                state.activeServer = configs.first(where: { $0.isActive }).map { ServerSnapshot(from: $0) }
                state.isLoadingPersistedState = false
                return configs.map(\.id)
            }
            await migrateCredentialsAccessibility(for: serverIDs)
        } catch {
            await MainActor.run { state.isLoadingPersistedState = false }
        }
    }

    /// Re-writes existing Keychain items with AfterFirstUnlock accessibility so
    /// that lock screen playback transitions can read credentials during KI-2 fix.
    /// Idempotent: safe to call on every cold start. Never blocks app boot.
    private func migrateCredentialsAccessibility(for serverIDs: [UUID]) async {
        for id in serverIDs {
            let key = ServerCredentials.keychainKey(for: id)
            do {
                guard let creds = try await keychain.retrieve(ServerCredentials.self, forKey: key) else {
                    Logger.server.warning("Keychain migration: no credential found for server id=\(id, privacy: .public), skipping")
                    continue
                }
                try await keychain.store(creds, forKey: key)
                Logger.server.info("Keychain migration: credential migrated for server id=\(id, privacy: .public)")
            } catch {
                Logger.server.warning("Keychain migration: skipped server id=\(id, privacy: .public) — \(error, privacy: .public)")
            }
        }
    }

    func testConnection() async throws {
        let client = try await makeSwiftSonicClient()
        try await client.ping()
    }

    func testConnection(
        url: String,
        username: String,
        password: String,
        customHeaders: [String: String]
    ) async throws {
        guard let serverURL = URL(string: url.trimmingCharacters(in: .whitespaces)),
              serverURL.scheme != nil, serverURL.host != nil else {
            throw ConnectionTestError.invalidURL
        }
        let transport = CustomHeadersTransport(headers: customHeaders)
        let client = SwiftSonicClient(
            configuration: ServerConfiguration(serverURL: serverURL, username: username, password: password),
            transport: transport,
            retryPolicy: .none,
            logSubsystem: "app.cassette.server"
        )
        do {
            try await client.ping()
        } catch {
            throw mapToConnectionTestError(error)
        }
        do {
            _ = try await client.getUser(username: username)
        } catch {
            throw mapToConnectionTestError(error)
        }
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
            configuration: ServerConfiguration(serverURL: url, username: snapshot.username, password: creds.password),
            transport: transport,
            logSubsystem: "app.cassette.server"
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

    func mapToConnectionTestError(_ error: Error) -> ConnectionTestError {
        guard let sonic = error as? SwiftSonicError else {
            let e = error as NSError
            Logger.server.error("Connection test failed — non-SwiftSonic error: domain=\(e.domain, privacy: .public) code=\(e.code, privacy: .public)")
            return .unknown(domain: e.domain, code: e.code)
        }

        // Log the raw underlying error details before any mapping.
        switch sonic {
        case .network(let urlError):
            Logger.server.error("Connection test failed — URLError code=\(urlError.code.rawValue, privacy: .public)")
        case .httpError(let statusCode, let endpoint, let serverHost):
            Logger.server.error("Connection test failed — HTTP \(statusCode, privacy: .public) endpoint=\(endpoint, privacy: .public) host=\(serverHost ?? "nil", privacy: .public)")
        case .api(let apiError):
            Logger.server.error("Connection test failed — Subsonic API error code=\(apiError.code.rawValue, privacy: .public) endpoint=\(apiError.endpoint, privacy: .public)")
        case .decoding(_, let rawData):
            Logger.server.error("Connection test failed — decoding error, rawData.count=\(rawData.count, privacy: .public)")
        case .rateLimited(let retryAfter, let endpoint, let serverHost):
            let retryAfterStr = retryAfter.map { "\($0)" } ?? "nil"
            Logger.server.error("Connection test failed — rate limited endpoint=\(endpoint, privacy: .public) host=\(serverHost ?? "nil", privacy: .public) retryAfterSecs=\(retryAfterStr, privacy: .public)")
        case .invalidConfiguration(let reason):
            Logger.server.error("Connection test failed — invalidConfiguration: \(reason, privacy: .public)")
        case .insecureRedirect(let from, let to):
            Logger.server.error("Connection test failed — insecureRedirect from=\(from.host ?? "nil", privacy: .public) to=\(to.host ?? "nil", privacy: .public)")
        }

        switch sonic {
        case .network(let urlError):
            if sonic.isDNSFailure { return .dnsFailure }
            if sonic.isCertificateError { return .certificate }
            switch urlError.code {
            case .appTransportSecurityRequiresSecureConnection:
                return .atsBlocked
            case .timedOut:
                return .timeout
            default:
                return .cannotConnect
            }
        case .httpError(let statusCode, _, _):
            if statusCode == 401 || statusCode == 403 { return .unauthorized }
            return .httpError(statusCode: statusCode)
        case .api(let apiError):
            if sonic.isAuthenticationFailure { return .unauthorized }
            return .subsonicError(code: apiError.code, message: apiError.message)
        case .decoding:
            return .notSubsonicServer
        case .rateLimited:
            return .httpError(statusCode: 429)
        case .invalidConfiguration:
            return .invalidConfiguration
        case .insecureRedirect:
            return .insecureRedirect
        }
    }

    private func validateHeaders(_ headers: [String: String]) throws {
        for (key, value) in headers {
            guard HeaderValidator.isValidName(key) else {
                throw CassetteError.invalidHeaderName(key: key)
            }
            guard HeaderValidator.isValidValue(value) else {
                throw CassetteError.invalidHeaderValue(key: key)
            }
        }
    }
}
