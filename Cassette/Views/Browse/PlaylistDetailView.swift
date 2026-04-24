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
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = PlaylistDetailViewModel(playlistId: playlist.id, libraryService: svc) }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: PlaylistDetailViewModel) -> some View {
        if vm.isLoading && vm.playlist == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.playlist == nil {
            ContentUnavailableView(
                "Unable to load playlist",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else {
            let loaded = vm.playlist
            let songs = loaded?.entry ?? []
            List {
                playlistHeader(loaded ?? PlaylistWithSongs(
                    id: playlist.id, name: playlist.name, comment: playlist.comment,
                    owner: playlist.owner, isPublic: playlist.isPublic,
                    songCount: playlist.songCount, duration: playlist.duration,
                    created: playlist.created, changed: playlist.changed,
                    coverArt: playlist.coverArt, entry: nil
                ))
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    PlaylistSongRow(song: song, index: index + 1)
                }
            }
            .listStyle(.plain)
        }
    }

    private func playlistHeader(_ playlist: PlaylistWithSongs) -> some View {
        VStack(spacing: 16) {
            CoverArtView(id: playlist.coverArt ?? playlist.id, size: 300)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)

            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.bold)
                if let owner = playlist.owner {
                    Text("by \(owner)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(playlist.songCount) track\(playlist.songCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // TODO(Étape 4): wire to PlayerService
            Button {
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .padding(.horizontal)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct PlaylistSongRow: View {
    let song: Song
    let index: Int

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
