// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import OSLog
import SwiftSonic

/// The Search tab.
///
/// CarPlay calls back on every keystroke, so each query cancels the one before it: a driver typing
/// six letters must not fire six searches at a server that may be on the other side of a tunnel.
@MainActor
final class CarPlaySearch: NSObject, CPSearchTemplateDelegate {
    private weak var library: CarPlayLibrary?
    private var pending: Task<Void, Never>?

    /// What each result row does, keyed by the row itself. CarPlay hands the selected item back
    /// rather than calling its handler, so the action has to be findable from the item alone.
    private var actions: [ObjectIdentifier: @MainActor () async -> Void] = [:]

    init(library: CarPlayLibrary) {
        self.library = library
        super.init()
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        pending?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, let library else {
            actions.removeAll()
            completionHandler([])
            return
        }

        pending = Task { @MainActor in
            do {
                let result = try await library.container.libraryService.search(query)
                guard !Task.isCancelled else { return }
                completionHandler(self.rows(for: result, library: library))
            } catch {
                guard !Task.isCancelled else { return }
                library.log(error, what: "search")
                completionHandler([])
            }
        }
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        guard let action = actions[ObjectIdentifier(item)] else {
            completionHandler()
            return
        }
        Task { @MainActor in
            await action()
            completionHandler()
        }
    }

    // MARK: - Results

    private func rows(for result: SearchResult3, library: CarPlayLibrary) -> [CPListItem] {
        actions.removeAll()
        var rows: [CPListItem] = []

        // Songs first: at the wheel, a search is almost always "play this track now".
        let tracks = (result.song ?? []).map { DisplayableSong(from: $0) }
        for (index, track) in tracks.enumerated() {
            rows.append(row(
                title: track.title,
                subtitle: track.artist,
                coverArtId: track.coverArtId,
                library: library
            ) { [weak library] in
                await library?.play(tracks, startIndex: index)
            })
        }

        for album in result.album ?? [] {
            rows.append(row(
                title: album.name,
                subtitle: album.artist ?? "Album",
                coverArtId: album.coverArt,
                library: library
            ) { [weak library] in
                await library?.openAlbum(album)
            })
        }

        for artist in result.artist ?? [] {
            rows.append(row(
                title: artist.name,
                subtitle: "Artist",
                coverArtId: artist.coverArt,
                library: library
            ) { [weak library] in
                await library?.openArtist(artist)
            })
        }

        return Array(rows.prefix(library.itemLimit))
    }

    private func row(
        title: String,
        subtitle: String?,
        coverArtId: String?,
        library: CarPlayLibrary,
        action: @escaping @MainActor () async -> Void
    ) -> CPListItem {
        let item = CPListItem(text: title, detailText: subtitle)
        CarPlayArtwork.attach(
            to: item,
            coverArtId: coverArtId,
            cache: library.container.artworkImageCache,
            size: CPListItem.maximumImageSize
        )
        actions[ObjectIdentifier(item)] = action
        return item
    }
}
#endif
