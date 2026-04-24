import Foundation
import SwiftSonic

protocol ServerServiceProtocol: AnyObject, Sendable {
    /// Observable UI state (MainActor-isolated). Access directly from SwiftUI views.
    var state: ServerState { get }

    func addServer(
        displayName: String,
        baseURL: String,
        username: String,
        password: String,
        customHeaders: [String: String]
    ) async throws

    /// Atomically removes server from SwiftData and Keychain.
    /// Performs best-effort rollback if one step fails after the other succeeds.
    func removeServer(id: UUID) async throws

    func setActiveServer(id: UUID) async throws

    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws

    /// Pings the active server via SwiftSonic. Throws if no active server or ping fails.
    func testConnection() async throws

    /// Returns a SwiftSonicClient configured with CustomHeadersTransport for the active server.
    /// Callers must NOT cache this client — always request a fresh one to pick up config changes.
    func makeSwiftSonicClient() async throws -> SwiftSonicClient

    /// Returns the stored credentials for the active server.
    /// Used by MediaResolver and DownloadService to inject headers into AVPlayer / URLSession.
    func activeCredentials() async throws -> ServerCredentials

    /// Restores servers and activeServer from SwiftData + Keychain on app launch.
    /// Sets state.isLoadingPersistedState = false when complete (even on failure).
    func loadPersistedState() async
}
