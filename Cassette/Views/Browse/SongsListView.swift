// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import OSLog

/// Library-wide "All Songs" list: every song (loaded via search3's empty-query wildcard), a Play/Shuffle-all
/// header, a persisted sort control, and an A–Z jump bar when sorted by title.
struct SongsListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: SongsListViewModel?
    /// Persisted sort — Title by default, plus Artist / Recently Added / Release Date.
    @AppStorage("cassette.songSort") private var songSort: SongSort = .title

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        #if os(iOS)
        .cassetteContentWidth()
        #endif
        .navigationTitle("Songs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SongSortMenu(sort: $songSort)
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = SongsListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    /// Songs in the chosen order, mapped for display (sort needs the raw `Song` fields).
    private func sortedSongs(_ vm: SongsListViewModel) -> [DisplayableSong] {
        songSort.sorted(vm.songs).map { DisplayableSong(from: $0) }
    }

    @ViewBuilder
    private func content(_ vm: SongsListViewModel) -> some View {
        if vm.isLoading && vm.songs.isEmpty {
            LoadingStateView()
        } else if container?.serverState.isOnline == false && vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "Connect to your server to browse all songs."
            )
        } else if let error = vm.error, vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Songs",
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "music.note",
                title: "No Songs",
                subtitle: "Your library appears to be empty."
            )
        } else {
            let songs = sortedSongs(vm)
            ScrollViewReader { proxy in
                List {
                    playShuffleHeader(songs)
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, index: index + 1, showCoverArt: true, isFavorite: isFavorite(song))
                            .contentShape(Rectangle())
                            .onTapGesture { play(songs, at: index) }
                            .id(song.id)
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.load() }
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    // The A–Z jump bar only makes sense when sorted by title.
                    if songSort == .title && songs.count >= 20 {
                        AlphabetJumpBar(
                            availableLetters: songs.availableAlphabetLetters(keyPath: \.title),
                            onLetterTap: { letter in
                                if let id = firstAlphabetItemID(forLetter: letter, in: songs, keyPath: \.title) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(id, anchor: .top)
                                    }
                                }
                            }
                        )
                        .padding(.trailing, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playShuffleHeader(_ songs: [DisplayableSong]) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
            } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
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
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.cassetteAccent)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.vertical, 4)
    }

    private func isFavorite(_ song: DisplayableSong) -> Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    private func play(_ songs: [DisplayableSong], at index: Int) {
        Task {
            do {
                try await container?.playerService.play(tracks: songs, startIndex: index)
            } catch {
                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
            }
        }
    }
}
