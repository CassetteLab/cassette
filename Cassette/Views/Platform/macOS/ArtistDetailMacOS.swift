// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftSonic

struct ArtistDetailMacOS: View {
    let artistId: String
    let artistName: String
    let coverArtId: String?
    var showBackButton: Bool = true

    init(artistId: String, artistName: String, coverArtId: String? = nil, showBackButton: Bool = true) {
        self.artistId = artistId
        self.artistName = artistName
        self.coverArtId = coverArtId
        self.showBackButton = showBackButton
    }

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ArtistDetailViewModel?

    private var effectiveCoverArtId: String? { vm?.artist?.coverArt ?? coverArtId }

    var body: some View {
        Group {
            if let vm {
                artistContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { artistToolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .task {
            guard let svc = container?.libraryService else { return }
            if vm == nil { vm = ArtistDetailViewModel(artistId: artistId, libraryService: svc) }
            await vm?.load()
        }
    }

    private func artistContent(_ vm: ArtistDetailViewModel) -> some View {
        let albums = vm.artist?.album ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroSection(vm: vm)
                if !albums.isEmpty {
                    CarouselSection(title: "Albums") {
                        ForEach(albums) { album in
                            CarouselAlbumCard(album: album)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .refreshable { await vm.load() }
    }

    // MARK: - Hero

    private func heroSection(vm: ArtistDetailViewModel) -> some View {
        HStack(alignment: .center, spacing: 32) {
            coverCircle
            heroMetadata(vm: vm)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 344)
    }

    private var coverCircle: some View {
        CoverArtView(
            id: effectiveCoverArtId ?? artistId,
            size: 480,
            placeholderSystemImage: "person.fill"
        )
        .frame(width: 240, height: 240)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private func heroMetadata(vm: ArtistDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.artist?.name ?? artistName)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)

                let count = vm.artist?.albumCount ?? vm.artist?.album?.count
                if let count {
                    Text("\(count) album\(count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task { await playAll(shuffle: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.cassetteAccent)

                Button {
                    Task { await playAll(shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 240)
    }

    // MARK: - Play all albums sequentially

    private func playAll(shuffle: Bool) async {
        guard let c = container, let albums = vm?.artist?.album else { return }
        var allTracks: [DisplayableSong] = []
        for album in albums {
            if let detail = try? await c.libraryService.album(id: album.id),
               let songs = detail.song {
                allTracks.append(contentsOf: songs.map { DisplayableSong(from: $0, isDownloaded: false) })
            }
        }
        guard !allTracks.isEmpty else { return }
        if shuffle && !c.playerState.isShuffled {
            await c.playerService.toggleShuffle()
        }
        try? await c.playerService.play(tracks: allTracks, startIndex: 0)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var artistToolbar: some ToolbarContent {
        if showBackButton {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.plain)
                .help("Back")
            }
        }
    }
}
#endif
