// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct FavoritesView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: FavoritesViewModel?

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
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if isEmpty {
            EmptyStateView(
                systemImage: "heart",
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
        }
    }

    @ViewBuilder
    private func songsSection(_ songs: [DisplayableSong]) -> some View {
        if !songs.isEmpty {
            Section("Songs") {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 1, showCoverArt: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
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
                    NavigationLink(destination: {
                        #if os(macOS)
                        AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                        #else
                        AlbumDetailView(album: album)
                        #endif
                    }) {
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
                    NavigationLink(destination: {
                        #if os(macOS)
                        ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
                        #else
                        ArtistDetailView(artist: artist)
                        #endif
                    }) {
                        ArtistRow(artist: artist)
                    }
                }
            }
        }
    }
}
