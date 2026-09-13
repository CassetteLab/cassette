// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import OSLog

struct FavoritesView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: FavoritesViewModel?
    @State private var songToAddToPlaylist: DisplayableSong?
    @State private var showDownloadWarning = false
    /// Count quoted by the warning — captured at tap time so the dialog can't show a stale number.
    @State private var downloadWarningCount = 0

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayModeInline()
        .onAppear {
            guard let container else { return }
            if viewModel == nil {
                viewModel = FavoritesViewModel(
                    libraryService: container.libraryService,
                    downloadService: container.downloadService,
                    toastService: container.toastService,
                    serverState: container.serverState
                )
            }
        }
        .task { await viewModel?.load() }
    }

    @ViewBuilder
    private func content(_ vm: FavoritesViewModel) -> some View {
        let isEmpty = vm.songs.isEmpty && vm.albums.isEmpty && vm.artists.isEmpty
        if vm.isLoading && isEmpty {
            LoadingStateView()
        } else if let error = vm.error, isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Favorites",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if isEmpty {
            EmptyStateView(
                systemImage: "star",
                title: "No favorites yet",
                subtitle: "Songs, albums, and artists you favorite will appear here."
            )
        } else {
            let displayableSongs = vm.songs.map { DisplayableSong(from: $0) }
            List {
                songsSection(vm, displayableSongs)
                albumsSection(vm.albums)
                artistsSection(vm.artists)
            }
            .listStyle(.plain)
            .miniPlayerBottomMargin()
            .refreshable { await vm.load() }
            .sheet(item: $songToAddToPlaylist) { song in
                AddToPlaylistSheet(song: song)
            }
            .bulkDownloadConfirmation(trackCount: downloadWarningCount, isPresented: $showDownloadWarning) {
                Task { await vm.downloadAll() }
            }
        }
    }

    @ViewBuilder
    private func songsSection(_ vm: FavoritesViewModel, _ songs: [DisplayableSong]) -> some View {
        if !songs.isEmpty {
            Section("Songs") {
                // Shuffle / Play / Download, sized exactly as the album and playlist headers:
                // 44pt Liquid Glass circles either side of the accent Play capsule. Those views
                // colour their glyphs from the cover's dominant colour; this list has no cover,
                // so the glyph is `.primary` and Play keeps its own accent defaults.
                HStack(spacing: CassetteSpacing.m) {
                    Button {
                        HapticFeedback.medium.trigger()
                        Task {
                            guard !songs.isEmpty else { return }
                            let idx = Int.random(in: 0..<songs.count)
                            try? await container?.playerService.play(tracks: songs, startIndex: idx)
                            if container?.playerState.isShuffled != true {
                                await container?.playerService.toggleShuffle()
                            }
                        }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.cassetteCellTitle)
                            .foregroundStyle(.primary)
                            .cassetteGlassButton(size: 44)
                    }
                    .disabled(songs.isEmpty)
                    .accessibilityLabel("Shuffle")

                    PlayButton(action: {
                        Task {
                            guard !songs.isEmpty else { return }
                            try? await container?.playerService.play(tracks: songs, startIndex: 0)
                        }
                    }, isDisabled: songs.isEmpty || vm.isDownloadingAll)
                    .frame(maxWidth: 220)

                    downloadAllButton(vm, totalCount: songs.count)
                }
                .buttonStyle(.borderless)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.vertical, 4)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 1, showCoverArt: true, isFavorite: true, onAddToPlaylist: { s in songToAddToPlaylist = s })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                do {
                                    try await container?.playerService.play(tracks: songs, startIndex: index)
                                } catch {
                                    Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                                }
                            }
                        }
                }
            }
        }
    }

    /// Icon-only "download every favorite song", styled like the album/playlist download button:
    /// 44pt glass, `arrow.down.circle` when nothing is local and `.dotted` once some of the list
    /// is. Starred songs only — favorited albums and artists are untouched. Those views offer a
    /// third, destructive state (a trash button wiping the album's downloads); that is not the
    /// same affordance here, so a fully-downloaded list simply disables the button.
    /// Icon-only means the accessibility label is all VoiceOver has to go on.
    private func downloadAllButton(_ vm: FavoritesViewModel, totalCount: Int) -> some View {
        Button {
            Task {
                // Re-count against disk on tap: the warning must quote what will actually be
                // fetched, not a number cached at load time.
                let remaining = await vm.refreshPendingDownloadCount()
                guard remaining > 0 else { return }
                if remaining > BulkDownload.confirmationThreshold {
                    downloadWarningCount = remaining
                    showDownloadWarning = true
                } else {
                    await vm.downloadAll()
                }
            }
        } label: {
            Image(systemName: vm.pendingDownloadCount < totalCount
                  ? "arrow.down.circle.dotted"
                  : "arrow.down.circle")
                .font(.cassetteCellTitle)
                .foregroundStyle(.primary)
                // Swapped for a spinner in place, so the row doesn't resize mid-batch.
                .opacity(vm.isDownloadingAll ? 0 : 1)
                .overlay { if vm.isDownloadingAll { ProgressView().controlSize(.small) } }
                .cassetteGlassButton(size: 44)
        }
        .disabled(vm.pendingDownloadCount == 0 || vm.isDownloadingAll)
        .accessibilityLabel(vm.isDownloadingAll
            ? Text("Downloading all favorite songs")
            : Text("Download all favorite songs"))
    }

    @ViewBuilder
    private func albumsSection(_ albums: [AlbumID3]) -> some View {
        if !albums.isEmpty {
            Section("Albums") {
                ForEach(albums) { album in
                    NavigationLink(value: HomeDestination.album(album)) {
                        AlbumRow(
                            albumId: album.id,
                            name: album.name,
                            artist: album.artist,
                            year: album.year,
                            coverArtId: album.coverArt
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func artistsSection(_ artists: [ArtistID3]) -> some View {
        if !artists.isEmpty {
            Section("Artists") {
                ForEach(artists) { artist in
                    NavigationLink(value: HomeDestination.artist(artist)) {
                        ArtistRow(artist: artist)
                    }
                }
            }
        }
    }
}
