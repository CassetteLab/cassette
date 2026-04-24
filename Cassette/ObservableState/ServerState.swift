// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

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
    // Prevents OnboardingView flash before persisted state is restored on launch.
    var isLoadingPersistedState: Bool = true
}
