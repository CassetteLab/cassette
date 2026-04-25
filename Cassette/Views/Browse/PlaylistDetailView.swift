// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct PlaylistDetailView: View {
    private let playlistId: String
    private let initialName: String

    init(playlist: Playlist) {
        playlistId = playlist.id
        initialName = playlist.name
    }

    init(playlist: DownloadedPlaylist) {
        playlistId = playlist.playlistId
        initialName = playlist.name
    }

    init(playlistId: String, name: String) {
        self.playlistId = playlistId
        self.initialName = name
    }

    @Environment(\.appContainer) private var container
    @State private var viewModel: PlaylistDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cassetteContentWidth()
        .navigationTitle(viewModel?.name ?? initialName)
        .navigationBarTitleDisplayModeInline()
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = PlaylistDetailViewModel(
                    playlistId: playlistId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: PlaylistDetailViewModel) -> some View {
        if vm.isLoading && vm.songs.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Playlist",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            List {
                playlistHeader(vm: vm)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                let serverId = container?.serverState.activeServer?.id ?? UUID()
                PlaylistSongRows(
                    songs: vm.songs,
                    serverId: serverId
                ) { index in
                    Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: index) }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    private func playlistHeader(vm: PlaylistDetailViewModel) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            CoverArtCard(
                id: vm.coverArtId ?? playlistId,
                size: 220,
                cornerRadius: CassetteCornerRadius.large
            )
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(vm.name)
                    .font(.cassetteDetailTitle)
                    .multilineTextAlignment(.center)
                if let owner = vm.owner {
                    Text("by \(owner)")
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(.secondary)
                }
                Text("\(vm.songs.count) track\(vm.songs.count == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                PlayButton(action: {
                    Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: 0) }
                }, isDisabled: vm.songs.isEmpty || vm.isDownloadingPlaylist)
                .frame(maxWidth: 400)

                if !vm.isOffline {
                    if vm.isDownloadingPlaylist {
                        Button { Task { await vm.cancelPlaylistDownload() } } label: {
                            Image(systemName: "xmark")
                                .font(.cassetteCellTitle)
                                .foregroundStyle(Color.cassetteAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.cassetteAccent.opacity(0.12))
                                .clipShape(Circle())
                        }
                    } else {
                        Button { Task { await vm.downloadPlaylist() } } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.cassetteCellTitle)
                                .foregroundStyle(Color.cassetteAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.cassetteAccent.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .disabled(vm.songs.isEmpty)
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, CassetteSpacing.l)

            if vm.isDownloadingPlaylist {
                HStack(spacing: CassetteSpacing.s) {
                    ProgressView().scaleEffect(0.8)
                    Text("Downloading…")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, CassetteSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Live download indicator rows

/// Sub-view that observes DownloadedTrack changes live via @Query,
/// overriding the isDownloaded flag per row without requiring a VM reload.
private struct PlaylistSongRows: View {
    let songs: [DisplayableSong]
    let onTap: (Int) -> Void

    @Query private var downloadedTracks: [DownloadedTrack]

    init(songs: [DisplayableSong], serverId: UUID, onTap: @escaping (Int) -> Void) {
        self.songs = songs
        self.onTap = onTap
        let sid = serverId
        _downloadedTracks = Query(
            filter: #Predicate<DownloadedTrack> { track in
                track.serverId == sid
            }
        )
    }

    private var downloadedSongIds: Set<String> {
        Set(downloadedTracks.map(\.songId))
    }

    var body: some View {
        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
            let liveDownloaded = downloadedSongIds.contains(song.id)
            let liveSong = DisplayableSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                albumName: song.albumName,
                duration: song.duration,
                trackNumber: song.trackNumber,
                isDownloaded: liveDownloaded,
                coverArtId: song.coverArtId
            )
            SongRow(song: liveSong, index: index + 1, showCoverArt: true)
                .contentShape(Rectangle())
                .onTapGesture { onTap(index) }
        }
    }
}
