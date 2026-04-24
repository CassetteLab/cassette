// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct PlaylistDetailView: View {
    let playlist: Playlist

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
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayModeInline()
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = PlaylistDetailViewModel(
                    playlistId: playlist.id,
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
        if vm.isLoading && vm.playlist == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.playlist == nil {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Playlist",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            let songs = vm.playlist?.entry ?? []
            ScrollView {
                LazyVStack(spacing: 0) {
                    playlistHeader(
                        coverArtId: playlist.coverArt ?? playlist.id,
                        name: playlist.name,
                        owner: playlist.owner,
                        songs: songs,
                        vm: vm
                    )

                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(
                            song: song,
                            index: index + 1,
                            showCoverArt: true,
                            isDownloaded: vm.downloadedSongIds.contains(song.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                        }
                        .padding(.horizontal, CassetteSpacing.l)

                        Divider()
                            .padding(.leading, CassetteSpacing.l)
                    }
                }
            }
            .refreshable { await vm.load() }
        }
    }

    private func playlistHeader(
        coverArtId: String,
        name: String,
        owner: String?,
        songs: [Song],
        vm: PlaylistDetailViewModel
    ) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            CoverArtCard(
                id: coverArtId,
                size: 220,
                cornerRadius: CassetteCornerRadius.large
            )
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(name)
                    .font(.cassetteDetailTitle)
                    .multilineTextAlignment(.center)
                if let owner {
                    Text("by \(owner)")
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(.secondary)
                }
                Text("\(songs.count) track\(songs.count == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                PlayButton(action: {
                    Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                }, isDisabled: songs.isEmpty)

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
                    .disabled(songs.isEmpty)
                }
            }
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

