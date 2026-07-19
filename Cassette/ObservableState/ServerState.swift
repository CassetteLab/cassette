// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    /// Base URL of this server's AudioMuse-AI instance, or nil when none is configured.
    /// Mirrored here so views can show or hide the mood features without a SwiftData fetch.
    let audioMuseURL: String?

    init(from config: ServerConfig) {
        self.id = config.id
        self.displayName = config.displayName
        self.baseURL = config.baseURL
        self.username = config.username
        self.serverVersion = config.serverVersion
        self.audioMuseURL = config.audioMuseURL
    }
}

/// Observable UI state for server connectivity. Updated by ServerService via MainActor.run.
@Observable
@MainActor
final class ServerState {
    var servers: [ServerSnapshot] = []
    var activeServer: ServerSnapshot?
    var isConnected: Bool = false
    /// Updated by NetworkMonitor. False when NWPathMonitor reports no connectivity.
    var isOnline: Bool = true
    /// Updated by NetworkMonitor. True when the connection is metered (cellular, hotspot).
    /// Default false — optimistic until the first NWPath update corrects it on launch (~100ms).
    var isExpensive: Bool = false
    // Prevents OnboardingView flash before persisted state is restored on launch.
    var isLoadingPersistedState: Bool = true
}
