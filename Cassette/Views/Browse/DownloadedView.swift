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
    }

    var body: some View {
        if albums.isEmpty && playlists.isEmpty {
            EmptyStateView(
                systemImage: "arrow.down.circle",
                title: "No Downloads",
                subtitle: "Download albums and playlists while online to listen offline."
            )
        } else {
            List {
                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink(destination: AlbumDetailView(albumId: album.albumId, albumName: album.name)) {
                                HStack(spacing: CassetteSpacing.m) {
                                    CoverArtCard(id: album.coverArtId ?? album.albumId, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.name)
                                            .font(.cassetteCellTitle)
                                            .lineLimit(1)
                                        if let artist = album.artist {
                                            Text(artist)
                                                .font(.cassetteCellSubtitle)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text("\(album.tracksCount) track\(album.tracksCount == 1 ? "" : "s")\(album.isComplete ? "" : " (incomplete)")")
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
