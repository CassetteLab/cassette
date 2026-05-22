// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct ArtistDetailView: View {
    let artist: ArtistID3

    @Namespace private var albumZoomNamespace
    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var viewModel: ArtistDetailViewModel?
    @State private var selectedOutOfLibraryArtist: SimilarArtistRecommendation?
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
                if let error = vm.error, vm.artist == nil {
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
                                    NavigationLink(value: HomeDestination.album(album)) {
                                        AlbumGridCell(
                                            album: album,
                                            zoomSourceId: album.id,
                                            zoomNamespace: albumZoomNamespace
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .task(id: album.id) {
                                        await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
                                    }
                                }
                            }
                            .padding(CassetteSpacing.l)

                            if vm.isLoadingSimilarArtists || !vm.similarArtists.isEmpty {
                                similarArtistsSection(vm: vm)
                                    .padding(.bottom, CassetteSpacing.l)
                            }
                        }
                        .refreshable { await vm.load() }
                    }
                }
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
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = ArtistDetailViewModel(
                    artistId: artist.id,
                    libraryService: c.libraryService,
                    recommendationService: c.recommendationService,
                    imageResolver: c.externalArtistImageResolver
                )
            }
            await viewModel?.load()
            await viewModel?.loadSimilarArtists()
        }
        .sheet(item: $selectedOutOfLibraryArtist) { rec in
            OutOfLibraryArtistSheet(
                artist: rec,
                imageURL: viewModel?.outOfLibraryArtistImages[rec.id] ?? nil,
                providers: container?.externalProvidersStore.load() ?? []
            )
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

    // MARK: - Similar Artists Section

    @ViewBuilder
    private func similarArtistsSection(vm: ArtistDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Similar Artists")
                .font(.cassetteSectionTitle)
                .padding(.horizontal, CassetteSpacing.m)

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
                    .padding(.horizontal, CassetteSpacing.m)
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
                    .padding(.horizontal, CassetteSpacing.m)
                }
            }
        }
    }
}

// MARK: - Out-of-library artist sheet

struct OutOfLibraryArtistSheet: View {
    let artist: SimilarArtistRecommendation
    let imageURL: URL?
    let providers: [ExternalReleaseProvider]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CassetteSpacing.l) {
                    ExternalCoverView(url: imageURL) {
                        ArtistPlaceholderView(name: artist.name, size: 120)
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .padding(.top, CassetteSpacing.l)

                    VStack(spacing: CassetteSpacing.xs) {
                        Text(artist.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("Not in your library")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }

                    externalLinksSection
                }
                .padding(CassetteSpacing.l)
            }
            .navigationTitle(artist.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var externalLinksSection: some View {
        VStack(spacing: CassetteSpacing.s) {
            if !providers.isEmpty {
                ForEach(providers) { provider in
                    if let url = provider.buildURL(artistName: artist.name, albumTitle: "") {
                        externalLinkButton(title: "View on \(provider.name)", url: url, secondary: false)
                    }
                }
            }

            if let mbid = artist.mbid {
                if let lbURL = URL(string: "https://listenbrainz.org/artist/\(mbid)/") {
                    externalLinkButton(
                        title: "View on ListenBrainz",
                        url: lbURL,
                        secondary: !providers.isEmpty
                    )
                }
                if let mbURL = URL(string: "https://musicbrainz.org/artist/\(mbid)") {
                    externalLinkButton(
                        title: "View on MusicBrainz",
                        url: mbURL,
                        secondary: !providers.isEmpty
                    )
                }
            }
        }
        .padding(.horizontal, CassetteSpacing.l)
    }

    private func externalLinkButton(title: String, url: URL, secondary: Bool) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
            }
            .font(.cassetteCellTitle)
            .padding(CassetteSpacing.m)
            .frame(maxWidth: .infinity)
            .background(secondary
                ? Color.secondary.opacity(0.08)
                : Color.cassetteAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
            .foregroundStyle(secondary ? Color.secondary : Color.cassetteAccent)
        }
        .buttonStyle(.plain)
    }
}
