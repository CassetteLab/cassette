// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

@Observable
@MainActor
final class PlaylistListViewModel {
    var playlists: [Playlist] = []
    var isLoading = false
    var error: UserFacingError?

    private let libraryService: any LibraryServiceProtocol

    /// Playlist kinds the user has hidden on this server. Pushed in from the persisted per-server
    /// filter rather than owned here, so the view model stays a plain view of what was fetched.
    var hiddenKinds: Set<PlaylistKind> = []
    private var classifier = PlaylistClassifier(moodPlaylistIds: [])

    init(libraryService: any LibraryServiceProtocol) {
        self.libraryService = libraryService
    }

    /// Points the filter at a server: its hidden kinds, and the mood ids cached for it.
    func applyFilter(hiddenKinds: Set<PlaylistKind>, serverId: UUID?) {
        self.hiddenKinds = hiddenKinds
        classifier = serverId.map { PlaylistClassifier(serverId: $0.uuidString) }
            ?? PlaylistClassifier(moodPlaylistIds: [])
    }

    /// Test seam: the same thing with a classifier built by hand.
    func applyFilter(hiddenKinds: Set<PlaylistKind>, classifier: PlaylistClassifier) {
        self.hiddenKinds = hiddenKinds
        self.classifier = classifier
    }

    /// Virtual "best of" playlists derived from the user's stars — never server playlists, so they are
    /// kept in their own section rather than mixed into `playlists`.
    var bestOfPlaylists: [ArtistBestOf] = []

    /// Loads the derived best-of playlists. Independent of `load()` and deliberately non-throwing: a server
    /// that fails or doesn't answer getStarred2 should cost the user the "Made For You" section, not the
    /// playlist list.
    func loadBestOf() async {
        guard let starred = try? await libraryService.getStarred2() else {
            bestOfPlaylists = []
            return
        }
        bestOfPlaylists = ArtistBestOf.all(in: starred.song ?? [])
    }

    // MARK: - Filtered output

    /// Server playlists the filter lets through, in the order the server returned them — the
    /// filter runs before any sectioning so the list below is built from what is actually shown.
    var visiblePlaylists: [Playlist] {
        guard !hiddenKinds.isEmpty else { return playlists }
        return playlists.filter { !hiddenKinds.contains(classifier.kind(of: $0)) }
    }

    /// The derived best-of entries, or none when that kind is hidden. No per-item work: they are
    /// all one kind by construction.
    var visibleBestOfPlaylists: [ArtistBestOf] {
        hiddenKinds.contains(.artistBestOf) ? [] : bestOfPlaylists
    }

    /// True when there are playlists to show and the filter is the only reason none are.
    ///
    /// Worth distinguishing: an empty list because the server has no playlists and an empty list
    /// because everything is hidden look identical, and only one of them is the user's own doing.
    var isEmptyBecauseFiltered: Bool {
        visiblePlaylists.isEmpty
            && visibleBestOfPlaylists.isEmpty
            && !(playlists.isEmpty && bestOfPlaylists.isEmpty)
    }

    /// Whether at least one kind is hidden, for the toolbar to say so.
    var isFiltering: Bool { !hiddenKinds.isEmpty }

    func load() async {
        isLoading = true
        error = nil
        do {
            playlists = try await libraryService.playlists()
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
