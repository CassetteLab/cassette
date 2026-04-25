// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct AlbumDetailView: View {
    let album: AlbumID3

    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumDetailViewModel?

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
        .navigationTitle(album.name)
        .navigationBarTitleDisplayModeInline()
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = AlbumDetailViewModel(
                    albumId: album.id,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: AlbumDetailViewModel) -> some View {
        if vm.isLoading && vm.album == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.album == nil {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Album",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            let loaded = vm.album ?? album
            let songs = loaded.song ?? []
            List {
                albumHeader(loaded, songs: songs, vm: vm)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(
                        song: song,
                        index: index + 1,
                        isDownloaded: vm.downloadedSongIds.contains(song.id)
                    )
                    .onTapGesture {
                        Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: CassetteSpacing.l, bottom: 0, trailing: CassetteSpacing.l))
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    private func albumHeader(_ album: AlbumID3, songs: [Song], vm: AlbumDetailViewModel) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            CoverArtCard(
                id: album.coverArt ?? album.id,
                size: 220,
                cornerRadius: CassetteCornerRadius.large
            )
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(album.name)
                    .font(.cassetteDetailTitle)
                    .multilineTextAlignment(.center)
                if let artist = album.artist {
                    Text(artist)
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: CassetteSpacing.s) {
                    if let year = album.year { Text(String(year)) }
                    if let genre = album.genre { Text("·"); Text(genre) }
                    Text("·"); Text("\(album.songCount) tracks")
                }
                .font(.cassetteCaption)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                PlayButton(action: {
                    Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                }, isDisabled: songs.isEmpty || vm.isDownloadingAlbum)
                .frame(maxWidth: 400)

                if vm.isDownloadingAlbum {
                    Button { Task { await vm.cancelAlbumDownload() } } label: {
                        Image(systemName: "xmark")
                            .font(.cassetteCellTitle)
                            .foregroundStyle(Color.cassetteAccent)
                            .frame(width: 44, height: 44)
                            .background(Color.cassetteAccent.opacity(0.12))
                            .clipShape(Circle())
                    }
                } else {
                    Button { Task { await vm.downloadAlbum() } } label: {
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

            if vm.isDownloadingAlbum {
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
