import Foundation
import Observation

/// Sendable value-type snapshot of a ServerConfig for crossing actor boundaries safely.
nonisolated struct ServerSnapshot: Sendable, Equatable {
    let id: UUID
    let displayName: String
    let baseURL: String
    let username: String
    let serverVersion: String?

    init(from config: ServerConfig) {
        self.id = config.id
        self.displayName = config.displayName
        self.baseURL = config.baseURL
        self.username = config.username
        self.serverVersion = config.serverVersion
    }
}

/// Observable UI state for server connectivity. Updated by ServerService via MainActor.run.
@Observable
@MainActor
final class ServerState {
    var servers: [ServerSnapshot] = []
    var activeServer: ServerSnapshot?
    var isConnected: Bool = false
}
