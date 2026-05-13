// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct ThemePlaylistDetailView: View {
    let dto: ThemePlaylistDTO
    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var songs: [DisplayableSong] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading && songs.isEmpty {
                LoadingStateView()
            } else if let error, songs.isEmpty {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to Load Playlist",
                    subtitle: error.localizedDescription,
                    action: .init(label: "Retry") { Task { await loadSongs() } }
                )
            } else {
                List {
                    header
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                        } label: {
                            SongRow(song: song, index: index + 1, showCoverArt: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .cassetteContentWidth()
        .navigationTitle(dto.type.displayName)
        .navigationBarTitleDisplayModeInline()
        .task(id: dto.playlistId) {
            await loadSongs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.m) {
            HStack(alignment: .top, spacing: CassetteSpacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous)
                        .fill(CassetteColors.accentBackground)
                        .frame(width: 80, height: 80)
                    Image(systemName: dto.type.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(CassetteColors.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(dto.title)
                        .font(.cassetteSectionTitle)
                        .lineLimit(2)
                    Text(dto.type.description)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(dto.trackCount) tracks")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if !songs.isEmpty {
                Button {
                    Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.cassetteCellTitle)
                        .padding(.horizontal, CassetteSpacing.m)
                        .padding(.vertical, CassetteSpacing.s)
                        .background(CassetteColors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(CassetteSpacing.m)
    }

    private func loadSongs() async {
        guard let playlistService = container?.playlistService else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await playlistService.getPlaylist(id: dto.playlistId)
            songs = (detail.entry ?? []).map { DisplayableSong(from: $0) }
            error = nil
        } catch {
            self.error = error
        }
    }
}
