// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct ArtistDetailView: View {
    let artist: ArtistID3

    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistDetailViewModel?
    @Query private var artistFavoriteMatches: [FavoriteRecord]

    init(artist: ArtistID3) {
        self.artist = artist
        let cid = "artist:\(artist.id)"
        _artistFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    private var isArtistFavorite: Bool { !artistFavoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: CassetteSpacing.l)
    ]

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                skeletonGrid
            }
        }
        .cassetteContentWidth()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeLarge()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    HapticFeedback.light.trigger()
                    Task {
                        if isArtistFavorite {
                            try? await container?.favoritesService.unstar(itemType: .artist, itemId: artist.id)
                        } else {
                            try? await container?.favoritesService.star(itemType: .artist, itemId: artist.id)
                        }
                    }
                } label: {
                    Image(systemName: isArtistFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isArtistFavorite ? Color.cassetteAccent : Color.primary)
                        .scaleEffect(isArtistFavorite ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isArtistFavorite)
                }
                .disabled(!isOnline)
            }
        }
        .task {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = ArtistDetailViewModel(artistId: artist.id, libraryService: svc) }
            await viewModel?.load()
        }
    }

    // MARK: - Hero

    private func heroSection(vm: ArtistDetailViewModel) -> some View {
        let albums = vm.artist?.album ?? []
        let count = albums.count
        return HStack(alignment: .center, spacing: CassetteSpacing.l) {
            CoverArtView(
                id: vm.artist?.coverArt ?? artist.id,
                size: 240,
                placeholderSystemImage: "person.fill"
            )
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("\(count) album\(count == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: CassetteSpacing.s) {
                    Button {
                        Task { await playAll(shuffled: false) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cassetteAccent)
                    .disabled(vm.isPlayLoading || albums.isEmpty)

                    Button {
                        Task { await playAll(shuffled: true) }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isPlayLoading || albums.isEmpty)
                }
            }
            .frame(height: 100)
        }
        .padding(.horizontal, CassetteSpacing.l)
        .padding(.top, CassetteSpacing.m)
        .padding(.bottom, CassetteSpacing.s)
    }

    private func playAll(shuffled: Bool) async {
        guard let c = container else { return }
        viewModel?.isPlayLoading = true
        defer { viewModel?.isPlayLoading = false }
        do {
            let tracks = try await c.libraryService.fetchAllTracks(forArtistID: artist.id)
            let queue = shuffled ? tracks.shuffled() : tracks
            try await c.playerService.play(tracks: queue, startIndex: 0)
        } catch CassetteError.artistTracksUnavailable {
            c.toastService.showError("Unable to load artist tracks. Please check your connection and try again.")
        } catch {
            c.toastService.showError("Playback failed. Please try again.")
        }
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: CassetteSpacing.l) {
                ForEach(0..<6, id: \.self) { _ in SkeletonAlbumCard() }
            }
            .padding(CassetteSpacing.l)
        }
    }

    @ViewBuilder
    private func content(_ vm: ArtistDetailViewModel) -> some View {
        if vm.isLoading && vm.artist == nil {
            skeletonGrid
        } else if let error = vm.error, vm.artist == nil {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artist",
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            let albums = vm.artist?.album ?? []
            if albums.isEmpty {
                EmptyStateView(
                    systemImage: "square.stack",
                    title: "No Albums",
                    subtitle: "This artist has no albums in the library."
                )
            } else {
                ScrollView {
                    heroSection(vm: vm)
                    LazyVGrid(columns: columns, spacing: CassetteSpacing.l) {
                        ForEach(albums) { album in
                            NavigationLink(destination: {
                                #if os(macOS)
                                AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                                #else
                                AlbumDetailView(album: album)
                                #endif
                            }) {
                                AlbumGridCell(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(CassetteSpacing.l)
                }
                .refreshable { await vm.load() }
            }
        }
    }
}

private struct AlbumGridCell: View {
    let album: AlbumID3

    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            GeometryReader { geo in
                CoverArtView(id: album.coverArt ?? album.id, size: Int(geo.size.width * 2))
                    .frame(width: geo.size.width, height: geo.size.width)
                    .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(album.name)
                .font(.cassetteCellTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let year = album.year {
                Text(String(year))
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: album.id) {
            coverImage = await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
        }
        .collectionContextMenu(
            itemType: .album,
            itemId: album.id,
            displayName: album.name,
            displaySubtitle: album.artist ?? "",
            coverArtId: album.coverArt,
            coverImage: coverImage,
            favoriteType: .album
        )
    }
}
