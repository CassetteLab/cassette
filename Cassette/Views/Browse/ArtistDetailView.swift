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
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.colorScheme) private var colorScheme
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground = false
    @State private var heroHeight: CGFloat = 680

    init(artist: ArtistID3) {
        self.artist = artist
        let cid = "artist:\(artist.id)"
        _artistFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    init(artistId: String, artistName: String, coverArtId: String?) {
        self.init(artist: ArtistID3(id: artistId, name: artistName, coverArt: coverArtId))
    }

    private var isArtistFavorite: Bool { !artistFavoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    // MARK: Theming — reuses the playlist/album dominant-color theme + ColorContrastUtils (no reimplementation).
    private var theme: PlaylistTheme { PlaylistTheme(dominantColor: dominantColor) }
    private var bodyColor: Color { theme.isThemed ? theme.dominantColor : systemBackgroundColor }
    private var headerTextColor: Color {
        dominantColor == .clear ? .primary : (isLightBackground ? .black : .white)
    }
    private var headerSecondaryColor: Color {
        dominantColor == .clear ? .secondary : (isLightBackground ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
    }
    private var heroButtonVariant: (background: Color, foreground: Color) {
        CassetteColors.heroButtonVariant(on: dominantColor)
    }
    private var systemBackgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
    /// The artist photo (server artist cover) drives the hero; falls back to the latest release's cover, then
    /// the artist id (placeholder glyph).
    private var heroCoverArtId: String {
        if let cover = viewModel?.artist?.coverArt, !cover.isEmpty { return cover }
        if let latest = latestReleaseCoverArtId { return latest }
        return artist.id
    }
    /// Cover of the most recent release (max year) — hero fallback + the featured release (Gate 2).
    private var latestReleaseCoverArtId: String? {
        (viewModel?.artist?.album ?? []).max(by: { ($0.year ?? 0) < ($1.year ?? 0) })?.coverArt
    }

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
                            artistHero(vm: vm)
                            VStack(spacing: 0) {
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
                            .frame(maxWidth: .infinity)
                            .background(bodyColor)
                            // Force the themed scheme so the shared album/similar cells contrast the tinted body.
                            .environment(\.colorScheme, theme.isThemed ? (theme.isLight ? .light : .dark) : colorScheme)
                        }
                        .ignoresSafeArea(.container, edges: .top)
                        .cassetteHideTopScrollEdgeEffect()
                        .background(bodyColor.ignoresSafeArea())
                        .refreshable { await vm.load() }
                        .task(id: heroCoverArtId) {
                            let cached = colorExtractor.dominantColor(for: heroCoverArtId, image: nil)
                            if cached != .clear {
                                dominantColor = cached
                                isLightBackground = cached.luminance > 0.6
                            } else {
                                await loadDominantColor(coverArtId: heroCoverArtId)
                            }
                        }
                    }
                }
            } else {
                skeletonGrid
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeInline()
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isThemed ? (theme.isLight ? .light : .dark) : nil, for: .navigationBar)
        #endif
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

    /// Immersive artist hero (reuses ImmersiveCoverHero + the dominant-color theme): the artist photo (server
    /// cover, else latest-release cover) full-bleed + the name + Play(=shuffle) + Favorite star floating over it.
    private func artistHero(vm: ArtistDetailViewModel) -> some View {
        let albums = vm.artist?.album ?? []
        let count = albums.count
        return ImmersiveCoverHero(
            coverArtId: heroCoverArtId,
            coverImage: nil,
            theme: theme,
            heroHeight: heroHeight
        ) {
            VStack(spacing: CassetteSpacing.s) {
                Text(artist.name)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .multilineTextAlignment(.center)
                Text("\(count) album\(count == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(headerSecondaryColor)
                    .padding(.bottom, CassetteSpacing.xs)
                HStack(spacing: CassetteSpacing.l) {
                    // Big white round Play (= shuffle) — just the play glyph.
                    Button {
                        Task { await playAll(shuffled: true) }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.cassetteAccent)
                            .offset(x: 2)
                            .frame(width: 66, height: 66)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isPlayLoading || albums.isEmpty)

                    // Smaller favorite star.
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
                        Image(systemName: isArtistFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isArtistFavorite ? Color.cassetteAccent : headerTextColor)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOnline)
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
        }
    }

    private func loadDominantColor(coverArtId: String) async {
        guard let image = await container?.artworkImageCache.load(coverArtId: coverArtId) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        withAnimation(.easeIn(duration: 0.2)) {
            dominantColor = color
            isLightBackground = color.luminance > 0.6
        }
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
            ExternalLinkOpener.open(url)
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
