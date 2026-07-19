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
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = FavoritesViewModel(libraryService: svc) }
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
                songsSection(displayableSongs)
                albumsSection(vm.albums)
                artistsSection(vm.artists)
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
            .sheet(item: $songToAddToPlaylist) { song in
                AddToPlaylistSheet(song: song)
            }
        }
    }

    @ViewBuilder
    private func songsSection(_ songs: [DisplayableSong]) -> some View {
        if !songs.isEmpty {
            Section("Songs") {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            try? await container?.playerService.play(tracks: songs, startIndex: 0)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
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
