// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct SearchView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: SearchViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Search")
        .onAppear {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = SearchViewModel(libraryService: svc) }
        }
    }

    @ViewBuilder
    private func content(_ vm: SearchViewModel) -> some View {
        List {
            if vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if let error = vm.error {
                Text(error.localizedDescription)
                    .font(.cassetteBody)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            } else if let results = vm.results {
                artistSection(results.artist ?? [])
                albumSection(results.album ?? [])
                songSection(results.song ?? [])
            } else if vm.query.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Search Your Library",
                    subtitle: "Search for artists, albums, or songs."
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .searchable(text: Binding(
            get: { vm.query },
            set: { vm.query = $0 }
        ), prompt: "Artists, albums, songs…")
        .task(id: vm.query) {
            await vm.search()
        }
        .navigationDestination(for: ArtistID3.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: AlbumID3.self) { album in
            AlbumDetailView(album: album)
        }
    }

    @ViewBuilder
    private func artistSection(_ artists: [ArtistID3]) -> some View {
        if !artists.isEmpty {
            Section("Artists") {
                ForEach(artists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumSection(_ albums: [AlbumID3]) -> some View {
        if !albums.isEmpty {
            Section("Albums") {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
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
    private func songSection(_ songs: [Song]) -> some View {
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
}
