// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    nonisolated(unsafe) private static var _bgTaskMoodService: MoodPlaylistService?
    #endif

    init() {
        #if os(iOS)
        // Marks each process start in the opt-in audio-session log, so a relaunch between two events is visible.
        AudioSessionLog.log("[APP] process start \(AudioSessionLog.environmentSummary())")
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
                let result = await service.runYearlyPlaylistSyncIfNeeded(serverId: serverId, calendar: .current)
                Logger.wrapped.info("BGTask result: \(String(describing: result), privacy: .public)")
                // Mood playlists ride along on this task rather than declaring a second identifier:
                // it already wakes roughly daily, which is the right granularity for "has Wednesday
                // passed yet", and a new identifier would need an Info.plist entry to match.
                if let moods = CassetteApp._bgTaskMoodService {
                    let moodResult = await moods.runWeeklySyncIfNeeded(serverId: serverId, calendar: .current)
                    Logger.moodPlaylists.info("BGTask result: \(String(describing: moodResult), privacy: .public)")
                }
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

    /// Hands the launched container to the BGTask handler and schedules the next run. Called once,
    /// from the shared launch, so it happens even when CarPlay starts the process without a window.
    static func attachBackgroundTasks(to container: AppContainer) {
        _bgTaskService = container.wrappedPlaylistService
        _bgTaskServerState = container.serverState
        _bgTaskMoodService = container.moodPlaylistService
        scheduleWrappedUpdate()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        // .toastOverlay() must be the INNERMOST modifier: a toast pill now renders a
                        // CoverArtView, which reads @Environment(ArtworkImageCache.self) / appContainer.
                        // An overlay's content only inherits environments applied AFTER the overlay
                        // modifier (envs applied to the primary content below it do NOT reach the
                        // overlay's own view). So the env injections must sit below .toastOverlay().
                        .toastOverlay()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                        .environment(container.toastService)
                } else {
                    ProgressView()
                }
            }
            .tint(CassetteColors.accent)
            #if os(iOS)
            // Hidden switches for the opt-in audio-session log (cassette://diagnostics/audio-session/…).
            // Any other URL is left alone, exactly as before this handler existed.
            .onOpenURL { url in
                AudioSessionDiagnosticsLinkHandler.handle(url)
            }
            #endif
            .onAppear {
                #if os(macOS)
                NSApplication.shared.windows
                    .first { $0.title == "Mini Player" }?
                    .close()
                #endif
            }
            .task {
                // The launch itself is shared with any other scene (CarPlay can start the process
                // without this window) and runs once per process: see AppLauncher. Reconnectivity
                // handling moved there too — it used to be a `.task(id: isOnline)` on this view.
                guard container == nil else { return }
                container = await AppContainer.launched()
            }
            #if os(macOS)
            .frame(minHeight: 580)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                guard let c = container else { return }
                // Stop AVAudioEngine synchronously — prevents HALC frame accumulation during teardown.
                c.playerService.stopAudioEngineSync()
                let sema = DispatchSemaphore(value: 0)
                Task {
                    await c.playerService.stop()
                    await c.nowPlayingService.stop()
                    sema.signal()
                }
                let result = sema.wait(timeout: .now() + 1.5)
                #if DEBUG
                if result == .timedOut {
                    Logger.boot.warning("[APP] Terminate handler timed out after 1.5s")
                }
                #endif
            }
            #endif
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Single trigger for cross-device continuation. The paused check lives inside the
            // actor, next to the mutation it guards.
            if newPhase == .active, let c = container {
                Task { _ = await c.playerService.restoreFromOtherDevice() }
            }
            #if os(iOS)
            AudioSessionLog.log("[APP] scenePhase \(oldPhase) → \(newPhase)")
            // `.inactive` is entered in both directions on iOS:
            //   active -> inactive -> background  (leaving)
            //   background -> inactive -> active  (returning)
            // Only the leaving path needs the kill guard. Flushing on the way back in
            // writes a position the session restore has not applied yet, and logs a
            // "flushed" line for a transition that never risked a kill.
            if oldPhase == .active, newPhase == .inactive, let c = container {
                Task { await c.playerService.saveCurrentPosition() }
                Logger.session.info("App inactive — position flushed (iOS kill guard)")
            }
            #endif
            guard newPhase == .background, let c = container else { return }
            let snapshot = SessionPayload(
                currentIndex: c.playerState.currentIndex,
                currentPosition: c.playerState.position,
                queue: c.playerState.queue,
                currentTrack: c.playerState.currentTrack,
                repeatMode: c.playerState.repeatMode
            )
            Task { await c.sessionService.save(playerState: snapshot) }
            Logger.session.info("App backgrounded — session flushed")
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands {
            CassetteCommands(container: container)
        }
        #endif

        #if os(macOS)
        CassetteSettingsScene(container: container)

        Window("Mini Player", id: "mini-player") {
            Group {
                if let container {
                    MiniPlayerWindowView()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                } else {
                    MiniPlayerWindowView()
                }
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 136)
        .defaultPosition(.topTrailing)
        .restorationBehavior(.disabled)
        #endif
    }
}
