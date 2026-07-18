// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// Backs the virtual "The best of <artist>" screen. There is no server playlist behind it — the track list is
/// recomputed from `getStarred2` on every load, so it always reflects the current stars.
@Observable
@MainActor
final class ArtistBestOfViewModel {
    var songs: [DisplayableSong] = []
    var isLoading = true
    var error: UserFacingError?
    /// True while the bulk download is walking the track list.
    var isDownloadingAll = false
    var downloadingIds: Set<String> = []

    /// The starred payload kept in its server form — `download(song:)` takes a SwiftSonic `Song`, and
    /// `DisplayableSong` can't be converted back.
    private var rawSongs: [Song] = []

    private let artistId: String
    private let artistName: String
    private let libraryService: any LibraryServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let serverState: ServerState

    init(
        artistId: String,
        artistName: String,
        libraryService: any LibraryServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        serverState: ServerState
    ) {
        self.artistId = artistId
        self.artistName = artistName
        self.libraryService = libraryService
        self.downloadService = downloadService
        self.serverState = serverState
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let starred = try await libraryService.getStarred2()
            rawSongs = (starred.song ?? []).filter {
                ArtistBestOf.matches($0, artistId: artistId, artistName: artistName)
            }
            songs = ArtistBestOf.songs(of: artistId, named: artistName, in: starred.song ?? [])
        } catch {
            self.error = UserFacingError.from(error)
        }
    }

    /// Downloads the whole list track by track.
    ///
    /// Deliberately NOT `download(playlist:)`: that persists a `DownloadedPlaylist` record keyed on a server
    /// playlist id, and this playlist has none. The tracks land as ordinary individual downloads — playable
    /// offline from the artist and album screens like any other — and the best-of itself stays purely derived.
    func downloadAll(songIds: [String]) async {
        isDownloadingAll = true
        defer { isDownloadingAll = false }
        await download(songIds: songIds)
    }

    func download(songIds: [String]) async {
        guard let serverId = serverState.activeServer?.id else { return }
        let byId = Dictionary(rawSongs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let alreadyDownloaded = await downloadService.downloadedSongIds(serverId: serverId)
        for id in songIds where !alreadyDownloaded.contains(id) {
            guard let song = byId[id] else { continue }
            downloadingIds.insert(id)
            try? await downloadService.download(song: song, serverId: serverId)
            downloadingIds.remove(id)
        }
    }

    func removeDownload(songId: String) async {
        guard let serverId = serverState.activeServer?.id else { return }
        try? await downloadService.remove(songId: songId, serverId: serverId)
    }
}
