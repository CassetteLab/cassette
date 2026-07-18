// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    @State private var selectedOutOfLibraryArtist: SimilarArtistRecommendation?
    @State private var isGeneratingMix = false
    /// Shared album ordering, persisted and reused by the global album list too.
    @AppStorage("cassette.albumSort") private var albumSort: AlbumSort = .recentlyAdded

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
            guard let c = container else { return }
            if vm == nil {
                vm = ArtistDetailViewModel(
                    artistId: artistId,
                    libraryService: c.libraryService,
                    recommendationService: c.recommendationService,
                    imageResolver: c.externalArtistImageResolver
                )
            }
            await vm?.load()
            await vm?.loadSimilarArtists()
            await vm?.loadArtistInfo()
        }
        .sheet(item: $selectedOutOfLibraryArtist) { rec in
            OutOfLibraryArtistSheet(
                artist: rec,
                imageURL: vm?.outOfLibraryArtistImages[rec.id] ?? nil,
                providers: container?.externalProvidersStore.load() ?? []
            )
        }
    }

    private func artistContent(_ vm: ArtistDetailViewModel) -> some View {
        let albums = vm.artist?.album ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroSection(vm: vm)

                // Biography sits right under the hero (the artist name), no header.
                if let bio = vm.biography {
                    ArtistBioView(bio: bio, lastFmURL: vm.lastFmURL)
                        .padding(.horizontal, 32)
                }

                if !albums.isEmpty {
                    albumsGridSection(albums)
                }

                let similar = vm.similarArtists
                if vm.isLoadingSimilarArtists || !similar.isEmpty {
                    similarArtistsSection(vm: vm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, CassetteMacOSLayout.playerBarReservedHeight / 2)
        }
        .refreshable { await vm.load() }
    }

    // MARK: - Albums grid

    /// Two fixed rows — the album grid scrolls horizontally (2×N).
    private var albumGridRows: [GridItem] {
        [GridItem(.fixed(230), spacing: 24),
         GridItem(.fixed(230), spacing: 24)]
    }

    @ViewBuilder
    private func albumsGridSection(_ albums: [AlbumID3]) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack {
                Text("Albums")
                    .font(.cassetteSectionTitle)
                Spacer()
                AlbumSortMenu(sort: $albumSort)
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: albumGridRows, alignment: .top, spacing: 24) {
                    ForEach(albumSort.sorted(albums)) { album in
                        NavigationLink(value: HomeDestination.album(album)) {
                            AlbumGridCell(album: album)
                                .frame(width: 180)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Similar Artists

    @ViewBuilder
    private func similarArtistsSection(vm: ArtistDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Similar Artists")
                .font(.cassetteSectionTitle)
                .padding(.horizontal, 32)

            if vm.isLoadingSimilarArtists {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: CassetteSpacing.m) {
                        ForEach(0..<8, id: \.self) { _ in
                            VStack(spacing: CassetteSpacing.xs) {
                                SkeletonBlock(width: 64, height: 64, cornerRadius: 32)
                                SkeletonBlock(width: 72, height: 10)
                            }
                            .frame(width: 80)
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .allowsHitTesting(false)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: CassetteSpacing.m) {
                        ForEach(vm.similarArtists) { rec in
                            Group {
                                if rec.inLibrary {
                                    NavigationLink(value: HomeDestination.artist(ArtistID3(id: rec.id, name: rec.name))) {
                                        SimilarArtistCell(
                                            recommendation: rec,
                                            externalImageURL: vm.outOfLibraryArtistImages[rec.id] ?? nil,
                                            onOutOfLibraryTap: { selectedOutOfLibraryArtist = rec }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    SimilarArtistCell(
                                        recommendation: rec,
                                        externalImageURL: vm.outOfLibraryArtistImages[rec.id] ?? nil,
                                        onOutOfLibraryTap: { selectedOutOfLibraryArtist = rec }
                                    )
                                }
                            }
                            .frame(width: 80)
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Hero

    private func heroSection(vm: ArtistDetailViewModel) -> some View {
        HStack(alignment: .center, spacing: 32) {
            coverCircle
            heroMetadata(vm: vm)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CassetteMacOSLayout.heroHeight)
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
                .disabled(vm.isPlayLoading || vm.artist?.album?.isEmpty ?? true)

                Button {
                    Task { await playAll(shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isPlayLoading || vm.artist?.album?.isEmpty ?? true)

                Button {
                    guard !isGeneratingMix else { return }
                    Task {
                        isGeneratingMix = true
                        await runInstantMix(from: .artist(id: artistId), using: container)
                        isGeneratingMix = false
                    }
                } label: {
                    if isGeneratingMix {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Instant Mix", systemImage: instantMixSymbol)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.artist?.album?.isEmpty ?? true || isGeneratingMix)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: 240)
    }

    // MARK: - Play all

    private func playAll(shuffle: Bool) async {
        guard let c = container else { return }
        vm?.isPlayLoading = true
        defer { vm?.isPlayLoading = false }
        do {
            let tracks = try await c.libraryService.fetchAllTracks(forArtistID: artistId)
            let queue = shuffle ? tracks.shuffled() : tracks
            try await c.playerService.play(tracks: queue, startIndex: 0)
        } catch CassetteError.artistTracksUnavailable {
            c.toastService.showError("Unable to load artist tracks. Please check your connection and try again.")
        } catch {
            c.toastService.showError("Playback failed. Please try again.")
        }
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
                .buttonStyle(.borderless)
                .help("Back")
            }
            .cassetteSharedBackgroundVisibility(.hidden)
        }
    }
}
#endif
