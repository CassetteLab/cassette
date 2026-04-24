// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct ArtistDetailView: View {
    let artist: ArtistID3

    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistDetailViewModel?

    private let columns = [
        GridItem(.flexible(), spacing: CassetteSpacing.l),
        GridItem(.flexible(), spacing: CassetteSpacing.l)
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
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeLarge()
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
    }
}
