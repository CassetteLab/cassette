// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData

struct DownloadedView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        Group {
            if let serverId = container?.serverState.activeServer?.id {
                DownloadedContent(serverId: serverId)
            } else {
                EmptyStateView(
                    systemImage: "arrow.down.circle",
                    title: "No Server",
                    subtitle: "Connect to a server to manage downloads."
                )
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Downloads")
    }
}

// MARK: - Content

private struct DownloadedContent: View {
    let serverId: UUID
    @Query private var albums: [DownloadedAlbum]
    @Query private var playlists: [DownloadedPlaylist]
    @Query private var tracks: [DownloadedTrack]

    init(serverId: UUID) {
        self.serverId = serverId
        let sid = serverId
        _albums = Query(
            filter: #Predicate<DownloadedAlbum> { album in album.serverId == sid },
            sort: [SortDescriptor(\DownloadedAlbum.name)]
        )
        _playlists = Query(
            filter: #Predicate<DownloadedPlaylist> { playlist in playlist.serverId == sid },
            sort: [SortDescriptor(\DownloadedPlaylist.name)]
        )
        _tracks = Query(filter: #Predicate<DownloadedTrack> { track in track.serverId == sid })
    }

    private var displayAlbums: [DownloadedAlbumDisplay] {
        DownloadedAlbumMerger.merge(records: albums, tracks: tracks)
    }

    var body: some View {
        if displayAlbums.isEmpty && playlists.isEmpty {
            EmptyStateView(
                systemImage: "arrow.down.circle",
                title: "Nothing downloaded",
                subtitle: "Albums and playlists you download will be available here, even offline."
            )
        } else {
            List {
                if !displayAlbums.isEmpty {
                    Section("Albums") {
                        ForEach(displayAlbums) { display in
                            NavigationLink(destination: AlbumDetailView(albumId: display.albumId, albumName: display.name)) {
                                HStack(spacing: CassetteSpacing.m) {
                                    CoverArtCard(id: display.coverArtId ?? display.albumId, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(display.name)
                                            .font(.cassetteCellTitle)
                                            .lineLimit(1)
                                        if let artist = display.artist {
                                            Text(artist)
                                                .font(.cassetteCellSubtitle)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text("\(display.downloadedTracksCount) track\(display.downloadedTracksCount == 1 ? "" : "s")")
                                            .font(.cassetteCaption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, CassetteSpacing.xs)
                            }
                        }
                    }
                }

                if !playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(playlists) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                HStack(spacing: CassetteSpacing.m) {
                                    CoverArtCard(id: playlist.coverArtId ?? playlist.playlistId, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.cassetteCellTitle)
                                            .lineLimit(1)
                                        Text("\(playlist.tracksCount) track\(playlist.tracksCount == 1 ? "" : "s")\(playlist.isComplete ? "" : " (incomplete)")")
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
            }
            .listStyle(.plain)
        }
    }
}
