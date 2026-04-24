// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

@main
struct CassetteApp: App {
    @State private var container: AppContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        .environment(\.appContainer, container)
                } else {
                    ProgressView()
                }
            }
            .task {
                guard container == nil else { return }
                guard let newContainer = try? AppContainer() else { return }
                container = newContainer
                await newContainer.serverService.loadPersistedState()
                await newContainer.nowPlayingService.start()
                newContainer.networkMonitor.start(serverState: newContainer.serverState)
                // Best-effort TTL eviction at launch — runs concurrently, never blocks UI.
                Task { await newContainer.cacheService.evictExpired() }
            }
        }
    }
}
