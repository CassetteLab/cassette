// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct PlaylistDetailView: View {
    let playlist: Playlist

    @Environment(\.appContainer) private var container
    @State private var viewModel: PlaylistDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = PlaylistDetailViewModel(
                    playlistId: playlist.id,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: PlaylistDetailViewModel) -> some View {
        if vm.isLoading && vm.playlist == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.playlist == nil {
            ContentUnavailableView {
                Label("Unable to load playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Retry") { Task { await vm.load() } }
            }
        } else {
            let songs = vm.playlist?.entry ?? []
            List {
                playlistHeader(
                    coverArtId: playlist.coverArt ?? playlist.id,
                    name: playlist.name,
                    owner: playlist.owner,
                    songs: songs,
                    vm: vm
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    PlaylistSongRow(
                        song: song,
                        index: index + 1,
                        isDownloaded: vm.downloadedSongIds.contains(song.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    private func playlistHeader(
        coverArtId: String,
        name: String,
        owner: String?,
        songs: [Song],
        vm: PlaylistDetailViewModel
    ) -> some View {
        VStack(spacing: 16) {
            CoverArtView(id: coverArtId, size: 300)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)

            VStack(spacing: 4) {
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)
                if let owner {
                    Text("by \(owner)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(songs.count) track\(songs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(songs.isEmpty)

                if vm.isDownloadingPlaylist {
                    Button {
                        Task { await vm.cancelPlaylistDownload() }
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await vm.downloadPlaylist() }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(songs.isEmpty)
                }
            }
            .padding(.horizontal)

            if vm.isDownloadingPlaylist {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct PlaylistSongRow: View {
    let song: Song
    let index: Int
    let isDownloaded: Bool

    var body: some View {
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
            Spacer()
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let duration = song.duration {
                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
