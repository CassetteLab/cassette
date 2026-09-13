// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
import SwiftSonic

@Observable
@MainActor
final class FavoritesViewModel {
    var songs: [Song] = []
    var albums: [AlbumID3] = []
    var artists: [ArtistID3] = []
    var isLoading = false
    var error: UserFacingError?
    /// How many favorite songs are still missing locally — drives the download-all button's
    /// enabled state. Refreshed after a load, after a batch, and again on tap.
    private(set) var pendingDownloadCount = 0
    /// True while a download-all batch is queueing.
    private(set) var isDownloadingAll = false

    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let toastService: ToastService
    private let serverState: ServerState

    init(
        libraryService: any LibraryServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        toastService: ToastService,
        serverState: ServerState
    ) {
        self.libraryService = libraryService
        self.downloadService = downloadService
        self.toastService = toastService
        self.serverState = serverState
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let starred = try await libraryService.getStarred2()
            songs = starred.song ?? []
            albums = starred.album ?? []
            artists = starred.artist ?? []
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
        await refreshPendingDownloadCount()
    }

    // MARK: - Download all

    /// Recomputes how many favorite songs are still missing locally and returns it. Called on tap
    /// as well as after a load, so a confirmation prompt quotes a live number.
    @discardableResult
    func refreshPendingDownloadCount() async -> Int {
        pendingDownloadCount = await pendingDownloads().count
        return pendingDownloadCount
    }

    /// Queues every not-yet-downloaded favorite song through the shared download pipeline.
    func downloadAll() async {
        guard !isDownloadingAll, let serverId = serverState.activeServer?.id else { return }
        let missing = await pendingDownloads()
        guard !missing.isEmpty else { return }
        isDownloadingAll = true
        defer { isDownloadingAll = false }
        toastService.show(String(localized: "Downloading \(missing.count) tracks"))
        Logger.download.info("Favorites: queueing \(missing.count, privacy: .public) tracks for download")
        await BulkDownload.run(missing, serverId: serverId, using: downloadService)
        await refreshPendingDownloadCount()
    }

    /// Starred SONGS only, minus what is on disk. Tracks belonging to favorited albums or artists
    /// are deliberately excluded — the button in this view means "my starred songs".
    private func pendingDownloads() async -> [Song] {
        guard let serverId = serverState.activeServer?.id else { return [] }
        let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
        return BulkDownload.missing(from: songs, downloadedIds: downloadedIds)
    }
}
