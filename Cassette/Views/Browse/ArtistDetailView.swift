// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct ArtistDetailView: View {
    let artist: ArtistID3

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var viewModel: ArtistDetailViewModel?
    @State private var selectedOutOfLibraryArtist: SimilarArtistRecommendation?
    @Query private var artistFavoriteMatches: [FavoriteRecord]
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.colorScheme) private var colorScheme
    @State private var dominantColor: Color = .clear
    /// Shared album ordering, persisted and reused by the global album list too.
    @AppStorage("cassette.albumSort") private var albumSort: AlbumSort = .recentlyAdded
    /// Discography layout: false = 2-row horizontal scroll (default), true = vertical grid (nicer for big
    /// catalogues where horizontal scrolling gets tedious).
    @AppStorage("cassette.artistAlbumsGrid") private var artistAlbumsGrid = false
    /// Fixed cover height — the artist photo NEVER resizes when the content below it grows.
    private let heroCoverHeight: CGFloat = 680
    /// Height of the collapsed content, measured while collapsed (also catches the async bio arriving).
    /// The hero grows DOWNWARD by the delta so expanding the bio pushes the page down while the cover
    /// stays put; collapsed artists (no/short bio) keep the transport at the cover's foot.
    @State private var heroCollapsedContentHeight: CGFloat = 336
    @State private var bioExpanded = false
    /// Shows a spinner in place of the Instant Mix button while a mix is being generated (anti-spam).
    @State private var isGeneratingMix = false
    /// Offset that bottom-aligns the COLLAPSED content to the cover's foot. Because it depends only on the
    /// collapsed height (frozen while expanded), the name stays put when the bio expands — the extra lines
    /// reveal downward from a fixed top instead of the whole block jumping. The hero itself has NO fixed
    /// height: the ZStack grows to fit the content, so the text is never height-constrained (no deadlock).
    private var heroContentTopInset: CGFloat { max(0, heroCoverHeight - heroCollapsedContentHeight) }

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
    private var headerTextColor: Color { theme.contentColor }
    private var headerSecondaryColor: Color { theme.secondaryContentColor }
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
        viewModel.flatMap { latestRelease($0) }?.coverArt
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
                        subtitle: LocalizedStringKey(error.displayMessage),
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
                            VStack(alignment: .leading, spacing: CassetteSpacing.xl) {
                                if let featured = latestRelease(vm) {
                                    featuredReleaseSection(featured)
                                }
                                if vm.isLoadingTopSongs {
                                    topSongsSkeleton
                                } else if !vm.topSongs.isEmpty {
                                    topSongsSection(vm: vm)
                                }
                                albumsSection(albums)
                                if vm.isLoadingSimilarArtists || !vm.similarArtists.isEmpty {
                                    similarArtistsSection(vm: vm)
                                }
                            }
                            .padding(.vertical, CassetteSpacing.l)
                            .frame(maxWidth: .infinity)
                            .background(bodyColor)
                            // Force the themed scheme so the shared cells contrast the tinted body.
                            .environment(\.colorScheme, theme.isThemed ? (theme.isLight ? .light : .dark) : colorScheme)
                        }
                        .ignoresSafeArea(.container, edges: .top)
                        .cassetteHideTopScrollEdgeEffect()
                        .background(bodyColor.ignoresSafeArea())
                        .refreshable { await vm.load() }
                        .task(id: heroCoverArtId) {
                            let cached = colorExtractor.bottomStripColor(for: heroCoverArtId, image: nil)
                            if cached != .clear {
                                dominantColor = cached
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
        .navigationTitle("")
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
            await viewModel?.loadTopSongs()
            await viewModel?.loadSimilarArtists()
            await viewModel?.loadArtistInfo()
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

    /// Immersive artist hero: a FIXED-height artist photo (server cover, else latest-release cover) with the
    /// name + Play(=shuffle) + Favorite floating over its lower part. Unlike `ImmersiveCoverHero`, the cover
    /// height is decoupled from the hero height — expanding the bio grows the hero DOWNWARD (pushing the page
    /// down) while the photo stays exactly the same size.
    private func artistHero(vm: ArtistDetailViewModel) -> some View {
        let albums = vm.artist?.album ?? []
        let count = albums.count
        return ZStack(alignment: .top) {
            // Fixed cover pinned to the top; it never resizes when the content below grows.
            GeometryReader { geo in
                // Stretchy header: grow the cover UPWARD on over-scroll instead of revealing the page color.
                let stretch = max(0, geo.frame(in: .global).minY)
                PlaylistThemedBackground(
                    coverArtId: heroCoverArtId,
                    coverImage: nil,
                    theme: theme,
                    heroHeight: heroCoverHeight
                )
                .frame(width: geo.size.width, height: heroCoverHeight + stretch)
                .offset(y: -stretch)
            }
            .frame(height: heroCoverHeight)

            // Content offset so its collapsed form bottom-aligns to the cover's foot. Expanding reveals the
            // extra lines DOWNWARD from this fixed top (the name doesn't move); the ZStack (no fixed height)
            // grows to fit, pushing the page down while the cover stays put.
            VStack(spacing: 0) {
                Color.clear.frame(height: heroContentTopInset)
                heroContent(vm: vm, count: count, albums: albums)
                    .padding(.horizontal, CassetteSpacing.l)
                    .padding(.bottom, CassetteSpacing.l)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        // Only track the collapsed baseline (drives the top inset). While expanded the
                        // baseline is frozen, so the name/top of the bio never move.
                        if !bioExpanded { heroCollapsedContentHeight = height }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The floating name / album count / biography / transport block that sits over the cover's lower part.
    private func heroContent(vm: ArtistDetailViewModel, count: Int, albums: [AlbumID3]) -> some View {
        VStack(spacing: CassetteSpacing.s) {
            Text(artist.name)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(headerTextColor)
                .multilineTextAlignment(.center)
            Text("\(count) albums")
                .font(.cassetteCaption)
                .foregroundStyle(headerSecondaryColor)
                .padding(.bottom, CassetteSpacing.xs)

            // Biography sits between the name and the Play disc, over the cover — a 3-line skeleton while
            // it loads, then the justified bio fades in (or the area collapses if there is none).
            if vm.isLoadingArtistInfo {
                ArtistBioSkeleton(centered: true)
                    .frame(maxWidth: 440)
                    .padding(.bottom, CassetteSpacing.xs)
                    .transition(.opacity)
            } else if let bio = vm.biography {
                ArtistBioView(
                    bio: bio,
                    lastFmURL: vm.lastFmURL,
                    textColor: headerSecondaryColor,
                    linkColor: headerTextColor,
                    centered: true,
                    onExpandedChange: { bioExpanded = $0 }
                )
                .frame(maxWidth: 440)
                .padding(.bottom, CassetteSpacing.xs)
                .transition(.opacity)
            }

            HStack(spacing: CassetteSpacing.l) {
                // Instant Mix — mirrors the favorite button on the right so the Play disc stays centred.
                // Shows a spinner while generating so a slow mix can't be spam-tapped.
                Button {
                    guard !isGeneratingMix else { return }
                    Task {
                        isGeneratingMix = true
                        await runInstantMix(from: .artist(id: artist.id), using: container)
                        isGeneratingMix = false
                    }
                } label: {
                    Group {
                        if isGeneratingMix {
                            ProgressView().controlSize(.small).tint(headerTextColor)
                        } else {
                            Image(systemName: instantMixSymbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(headerTextColor)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isOnline || albums.isEmpty || isGeneratingMix)

                // Big white round Play (= shuffle) — just the play glyph.
                Button {
                    Task { await playAll() }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 66, height: 66)
                        .overlay {
                            // The play glyph is KNOCKED OUT of the white disc (transparent — the hero shows
                            // through it), centred.
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
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
                        .foregroundStyle(isArtistFavorite ? .white : headerTextColor)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isOnline)
            }
        }
        // Cross-fade the skeleton into the bio (and grow the hero) smoothly when it resolves.
        .animation(.easeInOut(duration: 0.35), value: vm.isLoadingArtistInfo)
    }

    private func loadDominantColor(coverArtId: String) async {
        guard let image = await container?.artworkImageCache.load(coverArtId: coverArtId) else { return }
        let color = colorExtractor.bottomStripColor(for: coverArtId, image: image)
        withAnimation(.easeIn(duration: 0.2)) {
            dominantColor = color
        }
    }

    // MARK: - Body sections (Gate 2)

    /// The most recent release (max year) — featured + the hero fallback cover.
    private func latestRelease(_ vm: ArtistDetailViewModel) -> AlbumID3? {
        (vm.artist?.album ?? []).max(by: { ($0.year ?? 0) < ($1.year ?? 0) })
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.cassetteSectionTitle)
            .foregroundStyle(headerTextColor)
            .padding(.horizontal, CassetteSpacing.l)
    }

    /// Featured (latest) release — a prominent card, Apple-Music style.
    private func featuredReleaseSection(_ album: AlbumID3) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            sectionHeader("Latest Release")
            NavigationLink(value: HomeDestination.album(album)) {
                HStack(spacing: CassetteSpacing.m) {
                    CoverArtView(id: album.coverArt ?? album.id, size: 200)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        if let year = album.year {
                            Text(verbatim: "\(year)")
                                .font(.cassetteCaption)
                                .foregroundStyle(headerSecondaryColor)
                        }
                        Text(album.name)
                            .font(.cassetteCellTitle)
                            .foregroundStyle(headerTextColor)
                            .lineLimit(2)
                        Text("\(album.songCount) songs")
                            .font(.cassetteCaption)
                            .foregroundStyle(headerSecondaryColor)
                    }
                    Spacer(minLength: 0)
                }
                .padding(CassetteSpacing.m)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
                // Make the WHOLE card (incl. the Spacer / background) tappable — a styled label in a plain
                // NavigationLink otherwise only registers taps on the opaque content (cover/text), not the gaps.
                .contentShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
                .padding(.horizontal, CassetteSpacing.l)
            }
            .buttonStyle(.plain)
            .lazyCollectionContextMenu(
                itemType: .album,
                itemId: album.id,
                displayName: album.name,
                displaySubtitle: album.artist ?? "",
                coverArtId: album.coverArt ?? album.id,
                favoriteType: .album,
                songLoader: { await albumTracks(album) }
            )
        }
    }

    /// Top (most-played) songs ranking.
    private func topSongsSection(vm: ArtistDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            sectionHeader("Top Songs")
            VStack(spacing: 0) {
                ForEach(Array(vm.topSongs.prefix(5).enumerated()), id: \.element.id) { index, song in
                    Button {
                        Task { try? await container?.playerService.play(tracks: vm.topSongs, startIndex: index) }
                    } label: {
                        SongRow(
                            song: song,
                            index: index + 1,
                            showCoverArt: true,
                            showArtist: false,
                            titleColor: headerTextColor,
                            secondaryColor: headerSecondaryColor
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
        }
    }

    private var topSongsSkeleton: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            sectionHeader("Top Songs")
            VStack(spacing: CassetteSpacing.m) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: CassetteSpacing.m) {
                        SkeletonBlock(width: 44, height: 44, cornerRadius: CassetteCornerRadius.standard)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 180, height: 13, cornerRadius: 4)
                            SkeletonBlock(width: 120, height: 11, cornerRadius: 4)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
        }
        .allowsHitTesting(false)
    }

    /// Two fixed rows for the album grid — it scrolls horizontally (2×N), ordered by the sort preference.
    private var albumGridRows: [GridItem] {
        [GridItem(.fixed(196), spacing: CassetteSpacing.m),
         GridItem(.fixed(196), spacing: CassetteSpacing.m)]
    }

    /// Albums — sorted by the shared preference, shown either as a 2-row horizontal scroll or a vertical
    /// grid (toggle in the header); a sort menu and layout toggle sit beside the title.
    private func albumsSection(_ albums: [AlbumID3]) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack(spacing: CassetteSpacing.m) {
                sectionHeader("Albums")
                Spacer()
                AlbumSortMenu(sort: $albumSort, iconOnly: true)
                    .font(.cassetteSectionTitle)
                    .foregroundStyle(headerTextColor)
                Button {
                    artistAlbumsGrid.toggle()
                } label: {
                    Image(systemName: artistAlbumsGrid ? "rectangle.grid.1x2" : "square.grid.2x2")
                        .font(.cassetteSectionTitle)
                        .foregroundStyle(headerTextColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(artistAlbumsGrid ? "Horizontal view" : "Grid view")
                .padding(.trailing, CassetteSpacing.l)
            }
            if artistAlbumsGrid {
                LazyVGrid(columns: columns, spacing: CassetteSpacing.l) {
                    ForEach(albumSort.sorted(albums)) { album in albumCell(album, grid: true) }
                }
                .padding(.horizontal, CassetteSpacing.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: albumGridRows, alignment: .top, spacing: CassetteSpacing.m) {
                        ForEach(albumSort.sorted(albums)) { album in albumCell(album, grid: false) }
                    }
                    .padding(.horizontal, CassetteSpacing.l)
                }
            }
        }
    }

    /// An album cover cell, sized to fill its grid column (`grid: true`) or fixed 160pt wide for the
    /// horizontal row layout. Shared by both discography layouts.
    @ViewBuilder
    private func albumCell(_ album: AlbumID3, grid: Bool) -> some View {
        NavigationLink(value: HomeDestination.album(album)) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Group {
                    if grid {
                        CoverArtView(id: album.coverArt ?? album.id, size: 320)
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        CoverArtView(id: album.coverArt ?? album.id, size: 320)
                            .frame(width: 160, height: 160)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
                Text(album.name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(headerTextColor)
                    .lineLimit(1)
                if let year = album.year {
                    Text(verbatim: "\(year)")
                        .font(.cassetteCaption)
                        .foregroundStyle(headerSecondaryColor)
                }
            }
            .frame(width: grid ? nil : 160, alignment: .leading)
            .frame(maxWidth: grid ? .infinity : nil, alignment: .leading)
            .task(id: album.id) {
                await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
            }
        }
        .buttonStyle(.plain)
        .lazyCollectionContextMenu(
            itemType: .album,
            itemId: album.id,
            displayName: album.name,
            displaySubtitle: album.artist ?? "",
            coverArtId: album.coverArt ?? album.id,
            favoriteType: .album,
            songLoader: { await albumTracks(album) }
        )
    }

    /// Loads an album's tracks on demand for the context-menu play actions (online album fetch).
    private func albumTracks(_ album: AlbumID3) async -> [DisplayableSong] {
        guard let detail = try? await container?.libraryService.album(id: album.id) else { return [] }
        return detail.song?.map { DisplayableSong(from: $0) } ?? []
    }

    private func playAll() async {
        guard let c = container else { return }
        viewModel?.isPlayLoading = true
        defer { viewModel?.isPlayLoading = false }
        do {
            let tracks = try await c.libraryService.fetchAllTracks(forArtistID: artist.id)
            try await c.playerService.play(tracks: tracks.shuffled(), startIndex: 0)
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

// MARK: - Artist biography

/// The server biography, clamped to a few lines with a "Show more" toggle. Its own
/// view so the expand state never re-renders the whole artist screen. Shared by the
/// iOS and macOS artist screens.
struct ArtistBioView: View {
    let bio: String
    let lastFmURL: URL?
    /// Body text colour. Defaults to `.secondary` (over the solid body); the hero passes a
    /// themed colour so the bio reads over the cover.
    var textColor: Color = .secondary
    /// Colour of the "Show more" / Last.fm controls.
    var linkColor: Color = .secondary
    /// When true the bio centres itself (hero placement over the cover) instead of left-aligning.
    var centered: Bool = false
    /// Notifies the parent when the expand state flips (the hero uses it to grow downward, not upward).
    var onExpandedChange: (Bool) -> Void = { _ in }

    @State private var expanded = false
    @Environment(\.openURL) private var openURL

    /// Only offer the toggle when there is enough text to overflow three lines.
    private var isLong: Bool { bio.count > 140 }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: CassetteSpacing.s) {
            JustifiedText(text: bio, lineLimit: expanded ? 0 : 3, color: textColor)

            HStack(spacing: CassetteSpacing.m) {
                if isLong {
                    Button(expanded ? "Show less" : "Show more") {
                        let willExpand = !expanded
                        // Freeze the collapsed baseline BEFORE the layout grows, so the top inset stays put.
                        onExpandedChange(willExpand)
                        withAnimation(.easeInOut(duration: 0.3)) { expanded = willExpand }
                    }
                    .font(.cassetteCaption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(linkColor)
                }

                if !centered { Spacer() }

                if let lastFmURL {
                    Button { openURL(lastFmURL) } label: {
                        Label("Last.fm", systemImage: "arrow.up.right")
                            .font(.cassetteCaption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(linkColor)
                }
            }
        }
    }
}

/// A 4-line placeholder shown while the bio loads (≈ three clamped lines plus the Show-more row), so the
/// area reserves height and the bio fades in (resizing if shorter) instead of popping — mirroring the
/// similar-artists skeleton.
struct ArtistBioSkeleton: View {
    var centered: Bool = false
    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: CassetteSpacing.s) {
            SkeletonBlock(height: 13)
            SkeletonBlock(height: 13)
            SkeletonBlock(height: 13)
            SkeletonBlock(width: 200, height: 13)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
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
