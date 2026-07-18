// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData

/// "The best of <artist>" — the user's starred tracks for one artist, presented as a playlist.
///
/// Deliberately a lighter surface than `PlaylistDetailView`: there is no server playlist behind it, so
/// editing, reordering, renaming, deleting and playlist download have nothing to act on and are absent
/// rather than disabled. It borrows the same hero and track-row components so it still reads as a playlist.
struct ArtistBestOfView: View {
    let artistId: String
    let artistName: String
    let coverArtId: String?

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: ArtistBestOfViewModel?
    @State private var dominantColor: Color = .clear
    /// Live star state so unstarring a track from its context menu drops it out of the list at once.
    @Query(filter: #Predicate<FavoriteRecord> { $0.itemType == "song" })
    private var songFavorites: [FavoriteRecord]
    /// Unfiltered — the active server isn't known at init, so it's applied at read time (as PlaylistDetailView does).
    @Query private var downloadedTracks: [DownloadedTrack]

    private let heroHeight: CGFloat = 420

    private var theme: PlaylistTheme { PlaylistTheme(dominantColor: dominantColor) }
    private var headerTextColor: Color { theme.contentColor }
    private var headerSecondaryColor: Color { theme.secondaryContentColor }
    private var bodyColor: Color {
        if theme.isThemed { return theme.dominantColor }
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    private var effectiveCoverArtId: String { coverArtId ?? artistId }

    private var songs: [DisplayableSong] {
        ArtistBestOf.filteredByLocalStars(
            viewModel?.songs ?? [],
            starredSongIds: Set(songFavorites.map(\.itemId))
        )
    }

    var body: some View {
        Group {
            if let vm = viewModel, !vm.isLoading, songs.isEmpty {
                if let error = vm.error {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Favorites",
                        subtitle: LocalizedStringKey(error.displayMessage),
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                } else {
                    EmptyStateView(
                        systemImage: "heart",
                        title: "No Liked Songs",
                        subtitle: "Songs you favorite from this artist will appear here."
                    )
                }
            } else {
                trackList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayModeInline()
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isThemed ? (theme.isLight ? .light : .dark) : nil, for: .navigationBar)
        #endif
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = ArtistBestOfViewModel(
                    artistId: artistId,
                    artistName: artistName,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
        .task(id: effectiveCoverArtId) {
            let cached = colorExtractor.bottomStripColor(for: effectiveCoverArtId, image: nil)
            if cached != .clear {
                dominantColor = cached
            } else if let image = await container?.artworkImageCache.load(coverArtId: effectiveCoverArtId) {
                let color = colorExtractor.bottomStripColor(for: effectiveCoverArtId, image: image)
                withAnimation(.easeIn(duration: 0.2)) { dominantColor = color }
            }
        }
    }

    private var trackList: some View {
        List {
            ImmersiveCoverHero(
                coverArtId: effectiveCoverArtId,
                coverImage: nil,
                theme: theme,
                heroHeight: heroHeight
            ) {
                heroContent
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if let serverId = container?.serverState.activeServer?.id {
                PlaylistSongRows(
                    songs: songs,
                    serverId: serverId,
                    downloadingIds: viewModel?.downloadingIds ?? [],
                    titleColor: headerTextColor,
                    secondaryColor: headerSecondaryColor,
                    onTap: { index in play(from: index) },
                    onDownload: { id in Task { await viewModel?.download(songIds: [id]) } },
                    onRemoveDownload: { id in Task { await viewModel?.removeDownload(songId: id) } },
                    rowBackground: bodyColor
                )
            }
        }
        .listStyle(.plain)
        .ignoresSafeArea(.container, edges: .top)
        .cassetteHideTopScrollEdgeEffect()
        .background(bodyColor.ignoresSafeArea())
        .refreshable { await viewModel?.load() }
        .environment(\.colorScheme, theme.isThemed ? (theme.isLight ? .light : .dark) : colorScheme)
    }

    private var heroContent: some View {
        VStack(spacing: CassetteSpacing.s) {
            Text("The best of \(artistName)")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(headerTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CassetteSpacing.l)
            // Held back until the fetch resolves — the hero renders before it, and "0 songs" flashing
            // under the title reads like an empty playlist.
            if viewModel?.isLoading == false {
                Text("\(songs.count) songs")
                    .font(.cassetteCaption)
                    .foregroundStyle(headerSecondaryColor)
                    .padding(.bottom, CassetteSpacing.xs)
            }

            // Shuffle and download flank the Play disc so it stays centred, mirroring the artist hero.
            HStack(spacing: CassetteSpacing.l) {
                Button {
                    let shuffled = songs.shuffled()
                    Task { try? await container?.playerService.play(tracks: shuffled, startIndex: 0) }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
                .accessibilityLabel("Shuffle")

                Button {
                    play(from: 0)
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 66, height: 66)
                        .overlay {
                            // Glyph knocked out of the white disc, matching the artist hero's transport.
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
                .accessibilityLabel("Play")

                downloadButton
            }
        }
    }

    /// Downloads every track of the list individually (no playlist record — see the view model). Turns into
    /// a check once they're all on disk; per-track removal stays available from each row's context menu.
    private var downloadButton: some View {
        Button {
            let ids = songs.map(\.id)
            Task { await viewModel?.downloadAll(songIds: ids) }
        } label: {
            Group {
                if viewModel?.isDownloadingAll == true {
                    ProgressView().controlSize(.small).tint(headerTextColor)
                } else {
                    Image(systemName: allDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                }
            }
            .frame(width: 42, height: 42)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(songs.isEmpty || allDownloaded || viewModel?.isDownloadingAll == true)
        .accessibilityLabel("Download")
    }

    /// Every visible track already on disk for the active server.
    private var allDownloaded: Bool {
        guard !songs.isEmpty, let serverId = container?.serverState.activeServer?.id else { return false }
        let onDisk = Set(downloadedTracks.filter { $0.serverId == serverId }.map(\.songId))
        return songs.allSatisfy { onDisk.contains($0.id) }
    }

    private func play(from index: Int) {
        let tracks = songs
        guard tracks.indices.contains(index) else { return }
        Task { try? await container?.playerService.play(tracks: tracks, startIndex: index) }
    }
}
