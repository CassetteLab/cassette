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
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            } else if let results = vm.results {
                artistSection(results.artist ?? [])
                albumSection(results.album ?? [])
                songSection(results.song ?? [])
            } else if vm.query.isEmpty {
                ContentUnavailableView(
                    "Search your library",
                    systemImage: "magnifyingglass",
                    description: Text("Search for artists, albums, or songs.")
                )
                .listRowSeparator(.hidden)
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
                        HStack(spacing: 12) {
                            CoverArtView(id: artist.coverArt ?? artist.id, size: 44)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            Text(artist.name)
                        }
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
                        HStack(spacing: 12) {
                            CoverArtView(id: album.coverArt ?? album.id, size: 44)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                if let artist = album.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func songSection(_ songs: [Song]) -> some View {
        if !songs.isEmpty {
            Section("Songs") {
                ForEach(songs) { song in
                    HStack(spacing: 12) {
                        CoverArtView(id: song.coverArt ?? song.id, size: 44)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                            if let artist = song.artist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
