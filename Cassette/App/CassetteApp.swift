// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import OSLog
import Foundation
#if os(iOS)
import BackgroundTasks
#endif

@main
struct CassetteApp: App {
    @State private var container: AppContainer?
    @Environment(\.scenePhase) private var scenePhase

    // Statics for BGTask handler access — set once after AppContainer init.
    // nonisolated(unsafe) is intentional: the BGTask closure runs off-actor;
    // these are written once on MainActor and read in a non-isolated context.
    #if os(iOS)
    nonisolated(unsafe) private static var _bgTaskService: WrappedPlaylistService?
    nonisolated(unsafe) private static var _bgTaskServerState: ServerState?
    #endif

    init() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "app.cassette.wrapped.monthly-update",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask,
                  let service = CassetteApp._bgTaskService,
                  let serverState = CassetteApp._bgTaskServerState else {
                task.setTaskCompleted(success: false)
                return
            }
            let workTask = Task {
                let serverId = await MainActor.run { serverState.activeServer?.id.uuidString }
                guard let serverId else {
                    processingTask.setTaskCompleted(success: false)
                    return
                }
                let result = await service.runMonthlyUpdateIfNeeded(serverId: serverId, calendar: .current)
                Logger.wrapped.info("BGTask result: \(String(describing: result), privacy: .public)")
                processingTask.setTaskCompleted(success: true)
                CassetteApp.scheduleWrappedUpdate()
            }
            processingTask.expirationHandler = {
                workTask.cancel()
                Logger.wrapped.warning("BGTask expired — rescheduling for tomorrow")
                CassetteApp.scheduleWrappedUpdate()
            }
        }
        #endif
    }

    #if os(iOS)
    static func scheduleWrappedUpdate() {
        let request = BGProcessingTaskRequest(identifier: "app.cassette.wrapped.monthly-update")
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date().addingTimeInterval(24 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                        .toastOverlay()
                        .environment(container.toastService)
                } else {
                    ProgressView()
                }
            }
            .task {
                guard container == nil else { return }
                guard let newContainer = try? AppContainer() else { return }
                // Register remote commands before UI appears so lock screen controls
                // are available from the very first play, even on cold start.
                await newContainer.nowPlayingService.start()
                container = newContainer
                // loadPersistedState must complete before restoreSession so the active
                // server is known when prepareCurrentTrackForRestoration resolves the URL.
                await newContainer.serverService.loadPersistedState()
                await newContainer.playerService.restoreSession()
                newContainer.networkMonitor.start(serverState: newContainer.serverState)
                Task { await runCoverArtGarbageCollection(container: newContainer) }
                // Cold start fallback: primary trigger for Wrapped updates (BGTask is best-effort).
                // Fire-and-forget — must never block app launch.
                Task { await runWrappedUpdate(container: newContainer) }
                #if os(iOS)
                CassetteApp._bgTaskService = newContainer.wrappedPlaylistService
                CassetteApp._bgTaskServerState = newContainer.serverState
                CassetteApp.scheduleWrappedUpdate()
                #endif
            }
            .task(id: container?.serverState.isOnline) {
                guard let c = container, c.serverState.isOnline else { return }
                await c.playerService.handleNetworkRestored()
            }
            #if os(macOS)
            .frame(minHeight: 580)
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background, let c = container else { return }
            c.sessionService.save(playerState: c.playerState)
            Logger.session.info("App backgrounded — session flushed")
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CassetteCommands()
        }
        #endif

        #if os(macOS)
        CassetteSettingsScene(container: container)
        #endif
    }

    // MARK: - Cover art garbage collection

    @MainActor
    private func runCoverArtGarbageCollection(container: AppContainer) async {
        let context = container.modelContainer.mainContext
        var referencedIds: Set<String> = []

        let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
        for album in albums {
            if let id = album.coverArtId { referencedIds.insert(id) }
        }

        let tracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
        for track in tracks {
            if let id = track.coverArtId { referencedIds.insert(id) }
        }

        let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
        for playlist in playlists {
            if let id = playlist.coverArtId { referencedIds.insert(id) }
        }

        let pinned = (try? context.fetch(FetchDescriptor<PinnedItem>())) ?? []
        for item in pinned {
            if let id = item.coverArtId { referencedIds.insert(id) }
        }

        await container.downloadService.garbageCollectOrphanedCovers(referencedIds: referencedIds)
    }

    // MARK: - Wrapped update

    @MainActor
    private func runWrappedUpdate(container: AppContainer) async {
        guard let serverId = container.serverState.activeServer?.id.uuidString else { return }
        await container.wrappedPlaylistService.handleYearTransitionIfNeeded(serverId: serverId, calendar: .current)
        let result = await container.wrappedPlaylistService.runMonthlyUpdateIfNeeded(serverId: serverId, calendar: .current)
        Logger.wrapped.info("Cold start result: \(String(describing: result), privacy: .public)")
    }
}
