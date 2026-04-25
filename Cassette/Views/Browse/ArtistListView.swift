// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct ArtistListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                browseContent(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Artists")
        .navigationDestination(for: ArtistID3.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: AlbumID3.self) { album in
            AlbumDetailView(album: album)
        }
        .navigationDestination(for: OfflineArtistSummary.self) { summary in
            OfflineArtistAlbumsView(artist: summary)
        }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = ArtistListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func browseContent(_ vm: ArtistListViewModel) -> some View {
        if vm.isLoading && vm.indexes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if container?.serverState.isOnline == false && vm.indexes.isEmpty {
            if let serverId = container?.serverState.activeServer?.id {
                OfflineBrowseContent(serverId: serverId)
            } else {
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: "You're Offline",
                    subtitle: "Connect to your server to browse artists."
                )
            }
        } else if let error = vm.error, vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artists",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No Artists",
                subtitle: "Your library appears to be empty."
            )
        } else {
            List(vm.indexes, id: \.name) { index in
                Section(index.name) {
                    ForEach(index.artist) { artist in
                        NavigationLink(value: artist) {
                            ArtistRow(artist: artist)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Offline Browse

private nonisolated struct OfflineAlbumSummary: Sendable, Identifiable, Hashable {
    let albumId: String
    let albumName: String
    let artistName: String?
    let coverArtId: String?
    let trackCount: Int
    var id: String { albumId }
}

private nonisolated struct OfflineArtistSummary: Sendable, Identifiable, Hashable {
    let name: String
    let albums: [OfflineAlbumSummary]
    var id: String { name }
}

/// Derives the offline artist/album hierarchy from DownloadedTrack — the single source of truth
/// for all offline content, regardless of whether it came from an album or a playlist download.
private struct OfflineBrowseContent: View {
    let serverId: UUID
    @Query private var tracks: [DownloadedTrack]

    init(serverId: UUID) {
        self.serverId = serverId
        let sid = serverId
        _tracks = Query(
            filter: #Predicate<DownloadedTrack> { track in track.serverId == sid }
        )
    }

    private var artistSummaries: [OfflineArtistSummary] {
        let withAlbum = tracks.filter { $0.albumId != nil }
        let byAlbum = Dictionary(grouping: withAlbum) { $0.albumId! }
        let albumSummaries = byAlbum.map { albumId, albumTracks -> OfflineAlbumSummary in
            let first = albumTracks[0]
            return OfflineAlbumSummary(
                albumId: albumId,
                albumName: first.album ?? albumId,
                artistName: first.artist,
                coverArtId: first.coverArtId,
                trackCount: albumTracks.count
            )
        }
        let byArtist = Dictionary(grouping: albumSummaries) { $0.artistName ?? "Unknown Artist" }
        return byArtist.map { name, albums in
            OfflineArtistSummary(
                name: name,
                albums: albums.sorted { $0.albumName < $1.albumName }
            )
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        if tracks.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "No downloaded music available. Download albums or playlists while online to listen offline."
            )
        } else {
            List {
                Section("Downloaded Artists") {
                    ForEach(artistSummaries) { artist in
                        NavigationLink(value: artist) {
                            HStack(spacing: CassetteSpacing.m) {
                                Image(systemName: "music.mic")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.cassetteAccentSecondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.s))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                        .font(.cassetteCellTitle)
                                        .lineLimit(1)
                                    Text("\(artist.albums.count) album\(artist.albums.count == 1 ? "" : "s")")
                                        .font(.cassetteCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, CassetteSpacing.xs)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct OfflineArtistAlbumsView: View {
    let artist: OfflineArtistSummary

    var body: some View {
        List {
            ForEach(artist.albums) { album in
                NavigationLink(destination: AlbumDetailView(albumId: album.albumId, albumName: album.albumName)) {
                    AlbumRow(
                        albumId: album.albumId,
                        name: album.albumName,
                        artist: album.artistName,
                        year: nil,
                        coverArtId: album.coverArtId
                    )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeInline()
        .cassetteContentWidth()
    }
}
