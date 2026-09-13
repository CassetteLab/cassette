// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation
import OSLog
import SwiftSonic

@Observable
@MainActor
final class SongsListViewModel {
    /// The sorted, display-ready list — populated once loading finishes (or when the sort changes).
    private(set) var displaySongs: [DisplayableSong] = []
    /// Live count while paging, for the progress indicator.
    private(set) var loadedCount = 0
    /// True while pages are still being fetched.
    private(set) var isLoading = false
    /// True if the safety cap was hit (server has more songs than we loaded) — surfaced to the user.
    private(set) var didTruncate = false
    var error: UserFacingError?
    /// How many tracks in the list are still missing locally — drives the download-all button's
    /// enabled state. Refreshed after a load, after a batch, and again on tap.
    private(set) var pendingDownloadCount = 0
    /// True while a download-all batch is queueing.
    private(set) var isDownloadingAll = false
    /// Song ids whose own download is in flight, driving the per-row spinner. A bulk batch does
    /// not populate this: there, rows flip as each file lands, through the list's `@Query` — the
    /// same behaviour the album and playlist lists have.
    private(set) var downloadingIds: Set<String> = []

    private var rawSongs: [Song] = []
    private var currentSort: SongSort = .title
    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let toastService: ToastService
    private let serverState: ServerState

    /// 1000/page keeps the number of round-trips low while staying responsive. The cap is only a backstop
    /// against a server that ignores `songOffset` (metadata is light, so memory isn't the limit).
    private static let pageSize = 1000
    private static let safetyCap = 200_000

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

    /// Pages the whole library (server order), updating `loadedCount` as it goes, then sorts off-main.
    func load(sort: SongSort) async {
        currentSort = sort
        rawSongs = []
        displaySongs = []
        loadedCount = 0
        didTruncate = false
        error = nil
        isLoading = true
        defer { isLoading = false }

        var offset = 0
        var seen = Set<String>()
        do {
            while rawSongs.count < Self.safetyCap {
                let page = try await libraryService.allSongs(offset: offset, count: Self.pageSize)
                if page.isEmpty { break }
                // No-progress guard: if a full page adds no new ids, the server is ignoring the offset —
                // stop instead of looping forever.
                let fresh = page.filter { seen.insert($0.id).inserted }
                if fresh.isEmpty { break }
                rawSongs.append(contentsOf: fresh)
                loadedCount = rawSongs.count
                if page.count < Self.pageSize { break } // last (short) page
                offset += Self.pageSize
            }
            if rawSongs.count >= Self.safetyCap { didTruncate = true }
            Logger.library.info("All Songs loaded \(self.rawSongs.count, privacy: .public) songs (truncated=\(self.didTruncate, privacy: .public))")
        } catch {
            Logger.library.error("All Songs load failed: \(error, privacy: .public)")
            self.error = UserFacingError.from(error)
        }
        await recomputeDisplay()
        await refreshPendingDownloadCount()
    }

    /// Re-sorts the already-loaded songs (no network) when the user changes the sort.
    func changeSort(_ sort: SongSort) async {
        guard sort != currentSort else { return }
        currentSort = sort
        await recomputeDisplay()
    }

    // MARK: - Download all

    /// Recomputes how many tracks are still missing locally and returns it. Called on tap as well
    /// as after a load, so a confirmation prompt quotes a live number rather than a cached one.
    @discardableResult
    func refreshPendingDownloadCount() async -> Int {
        pendingDownloadCount = await pendingDownloads().count
        return pendingDownloadCount
    }

    /// Queues every not-yet-downloaded track in the list through the shared download pipeline.
    func downloadAll() async {
        guard !isDownloadingAll, let serverId = serverState.activeServer?.id else { return }
        let missing = await pendingDownloads()
        guard !missing.isEmpty else { return }
        isDownloadingAll = true
        defer { isDownloadingAll = false }
        toastService.show(String(localized: "Downloading \(missing.count) tracks"))
        Logger.download.info("All Songs: queueing \(missing.count, privacy: .public) tracks for download")
        await BulkDownload.run(missing, serverId: serverId, using: downloadService)
        await refreshPendingDownloadCount()
    }

    /// Downloads one track, mirroring the album and playlist detail views' row action.
    func downloadSong(id: String) async {
        guard let song = rawSongs.first(where: { $0.id == id }),
              let serverId = serverState.activeServer?.id else { return }
        downloadingIds.insert(id)
        defer { downloadingIds.remove(id) }
        do {
            try await downloadService.download(song: song, serverId: serverId)
        } catch {
            Logger.download.error("All Songs: download of '\(id, privacy: .public)' failed: \(error, privacy: .public)")
        }
        await refreshPendingDownloadCount()
    }

    /// Removes one downloaded track, so the row's context menu matches the detail views'.
    func removeDownload(id: String) async {
        guard let serverId = serverState.activeServer?.id else { return }
        do {
            try await downloadService.remove(songId: id, serverId: serverId)
        } catch {
            Logger.download.error("All Songs: removing download of '\(id, privacy: .public)' failed: \(error, privacy: .public)")
        }
        await refreshPendingDownloadCount()
    }

    /// The whole paged library minus what is already on disk — not just the rows scrolled into
    /// view, since `load` pages the entire list up front.
    private func pendingDownloads() async -> [Song] {
        guard let serverId = serverState.activeServer?.id else { return [] }
        let downloadedIds = await downloadService.downloadedSongIds(serverId: serverId)
        return BulkDownload.missing(from: rawSongs, downloadedIds: downloadedIds)
    }

    /// Sorts + maps off the main actor so large libraries never hitch the UI.
    private func recomputeDisplay() async {
        let raw = rawSongs
        let sort = currentSort
        displaySongs = await Task.detached(priority: .userInitiated) {
            sort.sorted(raw).map { DisplayableSong(from: $0) }
        }.value
    }
}
