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
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cassetteContentWidth()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeLarge()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
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

    @ViewBuilder
    private func content(_ vm: ArtistDetailViewModel) -> some View {
        if vm.isLoading && vm.artist == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.artist == nil {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artist",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            let albums = vm.artist?.album ?? []
            ScrollView {
                LazyVGrid(columns: columns, spacing: CassetteSpacing.l) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumGridCell(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(CassetteSpacing.l)
            }
            .refreshable { await vm.load() }
            .navigationDestination(for: AlbumID3.self) { album in
                AlbumDetailView(album: album)
            }
        }
    }
}

private struct AlbumGridCell: View {
    let album: AlbumID3

    @Environment(\.appContainer) private var container
    @State private var showLimitAlert = false

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
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let year = album.year {
                Text(String(year))
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if container?.pinService.isPinned(itemType: .album, itemId: album.id) == true {
                Button {
                    container?.pinService.unpin(itemType: .album, itemId: album.id)
                } label: {
                    Label("Unpin from Home", systemImage: "pin.slash")
                }
            } else {
                Button {
                    guard let serverId = container?.serverState.activeServer?.id,
                          let pin = container?.pinService else { return }
                    do {
                        try pin.pin(itemType: .album, itemId: album.id, displayName: album.name,
                                    displaySubtitle: album.artist ?? "", coverArtId: album.coverArt,
                                    serverId: serverId)
                    } catch PinError.limitReached {
                        showLimitAlert = true
                    } catch {}
                } label: {
                    Label("Pin to Home", systemImage: "pin")
                }
            }
        }
        .alert("Pin Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(PinError.limitReached.errorDescription ?? "")
        }
    }
}
