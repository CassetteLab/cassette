// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct SearchView: View {
    @Binding var searchQuery: String
    @Environment(\.appContainer) private var container
    @State private var viewModel: SearchViewModel?
    @AppStorage("cassette.recentSearches") private var recentSearchesData = "[]"

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentSearchesData.utf8))) ?? []
    }

    var body: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        Group {
            if trimmed.isEmpty && recentSearches.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Search your library",
                    subtitle: "Find songs, albums, artists, and playlists from your server."
                )
            } else if let vm = viewModel, !trimmed.isEmpty, !vm.isSearching,
                      let results = vm.searchResults, !hasAnyResults(results) {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a different search term."
                )
            } else {
                List {
                    if trimmed.isEmpty {
                        recentSearchesSection
                    } else if let vm = viewModel {
                        activeSearchContent(vm)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationDestination(for: ArtistID3.self) { artist in
            #if os(macOS)
            ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
            #else
            ArtistDetailView(artist: artist)
            #endif
        }
        .navigationDestination(for: AlbumID3.self) { album in
            #if os(macOS)
            AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
            #else
            AlbumDetailView(album: album)
            #endif
        }
        .onSubmit(of: .search) { addRecentSearch(searchQuery) }
        .onAppear {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = SearchViewModel(libraryService: svc) }
        }
        .task(id: searchQuery) {
            await viewModel?.search(query: searchQuery)
        }
        .cassetteContentWidth()
    }

    // MARK: - Idle state (recent searches)

    @ViewBuilder
    private var recentSearchesSection: some View {
        Section {
            ForEach(recentSearches, id: \.self) { query in
                Button {
                    searchQuery = query
                } label: {
                    Label(query, systemImage: "clock")
                        .font(.cassetteCellTitle)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            HStack {
                Text("Recent")
                    .font(.cassetteSectionTitle)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clear") { clearRecentSearches() }
                    .font(.cassetteBody)
                    .foregroundStyle(Color.cassetteAccent)
            }
            .textCase(nil)
        }
    }

    // MARK: - Active search state

    @ViewBuilder
    private func activeSearchContent(_ vm: SearchViewModel) -> some View {
        if vm.isSearching {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, CassetteSpacing.xl)
        } else if let error = vm.searchError {
            Text(error.localizedDescription)
                .font(.cassetteBody)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
        } else if let results = vm.searchResults, hasAnyResults(results) {
            artistResultsSection(results.artist ?? [])
            albumResultsSection(results.album ?? [])
            songResultsSection((results.song ?? []).map { DisplayableSong(from: $0) })
        }
    }

    private func hasAnyResults(_ results: SearchResult3) -> Bool {
        !(results.artist?.isEmpty ?? true) || !(results.album?.isEmpty ?? true) || !(results.song?.isEmpty ?? true)
    }

    @ViewBuilder
    private func artistResultsSection(_ artists: [ArtistID3]) -> some View {
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
    private func albumResultsSection(_ albums: [AlbumID3]) -> some View {
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
    private func songResultsSection(_ songs: [DisplayableSong]) -> some View {
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

    // MARK: - Recent searches

    private func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var searches = recentSearches
        searches.removeAll { $0 == trimmed }
        searches.insert(trimmed, at: 0)
        if searches.count > 10 { searches = Array(searches.prefix(10)) }
        recentSearchesData = (try? String(data: JSONEncoder().encode(searches), encoding: .utf8)) ?? "[]"
    }

    private func clearRecentSearches() {
        recentSearchesData = "[]"
    }
}
