// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import OSLog

@main
struct CassetteApp: App {
    @State private var container: AppContainer?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                } else {
                    ProgressView()
                }
            }
            .task {
                guard container == nil else { return }
                guard let newContainer = try? AppContainer() else { return }
                container = newContainer
                // loadPersistedState must complete before restoreSession so the active
                // server is known when prepareCurrentTrackForRestoration resolves the URL.
                await newContainer.serverService.loadPersistedState()
                await newContainer.playerService.restoreSession()
                await newContainer.nowPlayingService.start()
                newContainer.networkMonitor.start(serverState: newContainer.serverState)
                // Best-effort TTL eviction at launch — runs concurrently, never blocks UI.
                Task { await newContainer.cacheService.evictExpired() }
            }
            .task(id: container?.serverState.isOnline) {
                guard let c = container, c.serverState.isOnline else { return }
                await c.playerService.handleNetworkRestored()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background, let c = container else { return }
            c.sessionService.save(playerState: c.playerState)
            Logger.session.info("App backgrounded — session flushed")
        }
    }
}
