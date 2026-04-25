// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct AlbumDetailView: View {
    private let albumId: String
    private let initialName: String

    init(album: AlbumID3) {
        albumId = album.id
        initialName = album.name
    }

    init(album: DownloadedAlbum) {
        albumId = album.albumId
        initialName = album.name
    }

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
        .navigationTitle(viewModel?.albumName ?? initialName)
        .navigationBarTitleDisplayModeInline()
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = AlbumDetailViewModel(
                    albumId: albumId,
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
        if vm.isLoading && vm.songs.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Album",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            List {
                albumHeader(vm: vm)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                ForEach(Array(vm.songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 1)
                        .onTapGesture {
                            Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: index) }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: CassetteSpacing.l, bottom: 0, trailing: CassetteSpacing.l))
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    private func albumHeader(vm: AlbumDetailViewModel) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            CoverArtCard(
                id: vm.coverArtId ?? albumId,
                size: 220,
                cornerRadius: CassetteCornerRadius.large
            )
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(vm.albumName)
                    .font(.cassetteDetailTitle)
                    .multilineTextAlignment(.center)
                if let artist = vm.artistName {
                    Text(artist)
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: CassetteSpacing.s) {
                    if let year = vm.year { Text(String(year)) }
                    if let genre = vm.genre { Text("·"); Text(genre) }
                    Text("·"); Text("\(vm.songCount) tracks")
                }
                .font(.cassetteCaption)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                PlayButton(action: {
                    Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: 0) }
                }, isDisabled: vm.songs.isEmpty || vm.isDownloadingAlbum)
                .frame(maxWidth: 400)

                if !vm.isOffline {
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
                        .disabled(vm.songs.isEmpty)
                    }
                }
            }
            .buttonStyle(.borderless)
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
