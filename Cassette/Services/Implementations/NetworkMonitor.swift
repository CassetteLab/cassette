// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import Network
import OSLog

/// Wraps NWPathMonitor and keeps ServerState.isOnline in sync.
/// Start once from AppContainer; safe to call from any context.
final class NetworkMonitor: Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.cassette.network", qos: .utility)

    func start(serverState: ServerState) {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in serverState.isOnline = online }
        }
        monitor.start(queue: queue)
        Logger.network.debug("NetworkMonitor started.")
    }

    func stop() {
        monitor.cancel()
    }
}
