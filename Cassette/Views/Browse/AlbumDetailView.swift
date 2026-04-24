// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct AlbumDetailView: View {
    let album: AlbumID3

    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = AlbumDetailViewModel(albumId: album.id, libraryService: svc) }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: AlbumDetailViewModel) -> some View {
        if vm.isLoading && vm.album == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.album == nil {
            ContentUnavailableView(
                "Unable to load album",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else {
            let loaded = vm.album ?? album
            List {
                albumHeader(loaded)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                if let songs = loaded.song {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, index: index + 1)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func albumHeader(_ album: AlbumID3) -> some View {
        VStack(spacing: 16) {
            CoverArtView(id: album.coverArt ?? album.id, size: 300)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)

            VStack(spacing: 4) {
                Text(album.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                if let artist = album.artist {
                    Text(artist)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let year = album.year { Text(String(year)) }
                    if let genre = album.genre { Text("·"); Text(genre) }
                    Text("·"); Text("\(album.songCount) tracks")
                }
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

private struct SongRow: View {
    let song: Song
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(song.track ?? index)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
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
