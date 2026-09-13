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
        }
    }

    @ViewBuilder
    private func songsSection(_ vm: FavoritesViewModel, _ songs: [DisplayableSong]) -> some View {
        if !songs.isEmpty {
            Section("Songs") {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            try? await container?.playerService.play(tracks: songs, startIndex: 0)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            // White glyph/label on the accent-filled surface — `.borderedProminent`
                            // would otherwise pick its own foreground. Token, not a literal.
                            .foregroundStyle(Color.cassetteAccentText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cassetteAccent)

                    Button {
                        Task {
                            let idx = Int.random(in: 0..<songs.count)
                            try? await container?.playerService.play(tracks: songs, startIndex: idx)
                            if container?.playerState.isShuffled != true {
                                await container?.playerService.toggleShuffle()
                            }
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.cassetteAccent)

                    downloadAllButton(vm)
                }
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

    /// Icon-only "download every favorite song". Starred songs only — favorited albums and artists
    /// are untouched. Disabled once nothing is left to fetch. Icon-only means the accessibility
    /// label is the only thing VoiceOver has to go on.
    private func downloadAllButton(_ vm: FavoritesViewModel) -> some View {
        Button {
            Task { await vm.downloadAll() }
        } label: {
            Image(systemName: "arrow.down.circle")
                // Swapped for a spinner in place, so the row doesn't resize mid-batch.
                .opacity(vm.isDownloadingAll ? 0 : 1)
                .overlay { if vm.isDownloadingAll { ProgressView().controlSize(.small) } }
        }
        .buttonStyle(.bordered)
        .tint(Color.cassetteAccent)
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
