// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct DiscoverView: View {
    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var vm: DiscoverViewModel?
    @Namespace private var recentlyPlayedNS
    @Namespace private var mostPlayedNS
    @State private var yearlyPlaylists: [WrappedYearlyPlaylist] = []
    @State private var radioStations: [InternetRadioStation] = []
    #if os(iOS)
    @Namespace private var freshReleaseZoomNamespace
    #else
    @State private var selectedRelease: AlbumRecommendation?
    #endif
    @State private var showAllFreshReleases = false
    @State private var allReleasesVM: AllFreshReleasesViewModel?
    @State private var isListenBrainzConnected: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CassetteSpacing.l) {
                if let vm {
                    if vm.isErrorState {
                        errorBanner(vm: vm)
                    } else {
                        freshReleasesSection(vm: vm)
                        recentlyPlayedSection(vm: vm)
                        mostPlayedSection(vm: vm)
                    }
                    smartShuffleSection
                    wrappedSection
                    internetRadioSection
                }
            }
            .padding(.vertical, CassetteSpacing.m)
        }
        .cassetteContentWidth()
        .navigationTitle("Discover")
        .task {
            guard let container else { return }
            if vm == nil {
                vm = DiscoverViewModel(
                    libraryService: container.libraryService,
                    recommendationService: container.recommendationService
                )
            }
            if allReleasesVM == nil {
                allReleasesVM = AllFreshReleasesViewModel(recommendationService: container.recommendationService)
            }
            await vm?.load()
            isListenBrainzConnected = await container.listenBrainzService.currentSnapshot().isEnabled
            await vm?.loadFreshReleases()
            guard let serverId = container.serverState.activeServer?.id.uuidString else { return }
            yearlyPlaylists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverId)
            radioStations = (try? await container.radioService.listStations(forceRefresh: false)) ?? []
        }
        .refreshable {
            await vm?.load(forceRefresh: true)
            isListenBrainzConnected = await container?.listenBrainzService.currentSnapshot().isEnabled ?? false
            await vm?.loadFreshReleases()
        }
        #if os(iOS)
        .navigationDestination(for: AlbumRecommendation.self) { release in
            FreshReleaseDetailView(
                release: release,
                providers: container?.externalProvidersStore.load() ?? []
            )
            .cassetteZoomTransition(
                sourceID: release.id ?? "\(release.artistName)-\(release.title)",
                in: freshReleaseZoomNamespace
            )
        }
        #else
        .sheet(isPresented: Binding(
            get: { selectedRelease != nil },
            set: { if !$0 { selectedRelease = nil } }
        )) {
            if let release = selectedRelease {
                NavigationStack {
                    FreshReleaseDetailView(release: release, providers: container?.externalProvidersStore.load() ?? [])
                }
            }
        }
        #endif
        .navigationDestination(isPresented: $showAllFreshReleases) {
            if let vm = allReleasesVM {
                AllFreshReleasesView(vm: vm)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func freshReleasesSection(vm: DiscoverViewModel) -> some View {
        #if os(iOS)
        FreshReleasesCard(
            releases: vm.freshReleases,
            isLoading: vm.isLoadingFreshReleases,
            isListenBrainzConnected: isListenBrainzConnected,
            onSeeAll: { showAllFreshReleases = true },
            zoomNamespace: freshReleaseZoomNamespace
        )
        #else
        FreshReleasesCard(
            releases: vm.freshReleases,
            isLoading: vm.isLoadingFreshReleases,
            isListenBrainzConnected: isListenBrainzConnected,
            onSeeAll: { showAllFreshReleases = true },
            onTap: { release in selectedRelease = release }
        )
        #endif
    }

    private func recentlyPlayedSection(vm: DiscoverViewModel) -> some View {
        #if os(macOS)
        Group {
            if vm.isInitialLoading {
                section(title: "Recently Played") { skeletonScroll() }
            } else if vm.recentlyPlayed.isEmpty {
                section(title: "Recently Played") {
                    emptyStateMessage("No history yet — start playing some tracks.")
                }
            } else {
                CarouselSection(title: "Recently Played") {
                    ForEach(vm.recentlyPlayed, id: \.id) { album in
                        CarouselAlbumCard(album: album)
                    }
                }
            }
        }
        #else
        section(title: "Recently Played") {
            if vm.isInitialLoading {
                skeletonScroll()
            } else if vm.recentlyPlayed.isEmpty {
                emptyStateMessage("No history yet — start playing some tracks.")
            } else {
                horizontalAlbumScroll(albums: vm.recentlyPlayed, namespace: recentlyPlayedNS)
            }
        }
        #endif
    }

    private func mostPlayedSection(vm: DiscoverViewModel) -> some View {
        #if os(macOS)
        Group {
            if vm.isInitialLoading {
                section(title: "Most Played") { skeletonScroll() }
            } else if vm.mostPlayed.isEmpty {
                section(title: "Most Played") {
                    emptyStateMessage("No frequent plays yet — your top tracks will appear here.")
                }
            } else {
                CarouselSection(title: "Most Played") {
                    ForEach(vm.mostPlayed, id: \.id) { album in
                        CarouselAlbumCard(album: album)
                    }
                }
            }
        }
        #else
        section(title: "Most Played") {
            if vm.isInitialLoading {
                skeletonScroll()
            } else if vm.mostPlayed.isEmpty {
                emptyStateMessage("No frequent plays yet — your top tracks will appear here.")
            } else {
                horizontalAlbumScroll(albums: vm.mostPlayed, namespace: mostPlayedNS)
            }
        }
        #endif
    }

    private var smartShuffleSection: some View {
        section(title: "Smart Shuffle") {
            Button {
                Task { await triggerSmartShuffle() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    Image(systemName: "shuffle.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rediscover Your Library")
                            .font(.cassetteCellTitle)
                        Text("Tracks you haven't heard recently")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(CassetteSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cassetteAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, CassetteSpacing.m)
        }
    }

    private func triggerSmartShuffle() async {
        guard let container else { return }
        do {
            try await container.playerService.playSmartShuffle()
        } catch {
            container.toastService.showError(smartShuffleErrorMessage(from: error))
        }
    }

    private func smartShuffleErrorMessage(from error: Error) -> String {
        if case CassetteError.smartShuffleEmpty = error {
            return "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."
        }
        return "Smart Shuffle failed. Please try again."
    }

    private var wrappedSection: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack {
                Text("Wrapped")
                    .font(.cassetteSectionTitle)
                Spacer(minLength: 0)
                NavigationLink {
                    WrappedYearlyListView()
                } label: {
                    Text("See all")
                        .font(.cassetteCaption)
                        .foregroundStyle(Color.cassetteAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CassetteSpacing.m)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CassetteSpacing.s) {
                    ForEach(yearlyPlaylists) { playlist in
                        WrappedYearlyCard(playlist: playlist)
                    }
                    if let year = currentYearCardYear {
                        WrappedCurrentYearCard(year: year)
                    }
                    ForEach(currentYearMonths, id: \.month) { item in
                        WrappedRecapMonthCard(period: .month(year: item.year, month: item.month))
                    }
                }
                .padding(.horizontal, CassetteSpacing.m)
            }
        }
    }

    private var currentYearCardYear: Int? {
        let year = Calendar.current.component(.year, from: Date())
        guard !yearlyPlaylists.contains(where: { $0.year == year }) else { return nil }
        return year
    }

    private var currentYearMonths: [(year: Int, month: Int)] {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        return (1...currentMonth).reversed().map { (year, $0) }
    }

    private var internetRadioSection: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack {
                Text("Internet Radio")
                    .font(.cassetteSectionTitle)
                Spacer(minLength: 0)
                NavigationLink {
                    RadioListView()
                } label: {
                    Text("See all")
                        .font(.cassetteCaption)
                        .foregroundStyle(Color.cassetteAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CassetteSpacing.m)

            if radioStations.isEmpty {
                NavigationLink {
                    RadioListView()
                } label: {
                    HStack(spacing: CassetteSpacing.s) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(Color.cassetteAccent)
                        Text("Browse Stations")
                            .font(.cassetteCellTitle)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(CassetteSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cassetteAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, CassetteSpacing.m)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: CassetteSpacing.s) {
                        ForEach(radioStations, id: \.id) { station in
                            RadioCard(station: station)
                        }
                    }
                    .padding(.horizontal, CassetteSpacing.m)
                }
            }
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text(title)
                .font(.cassetteSectionTitle)
                .padding(.horizontal, CassetteSpacing.m)
            content()
        }
    }

    private func horizontalAlbumScroll(albums: [AlbumID3], namespace: Namespace.ID) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CassetteSpacing.s) {
                ForEach(albums, id: \.id) { album in
                    NavigationLink {
                        #if os(macOS)
                        AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                        #else
                        AlbumDetailView(
                            album: album,
                            zoomSourceId: album.id,
                            zoomNamespace: namespace,
                            initialCoverImage: artworkImageCache.cachedImage(for: album.coverArt ?? album.id)
                        )
                        #endif
                    } label: {
                        AlbumCard(album: album)
                            .cassetteMatchedTransitionSource(id: album.id, in: namespace)
                            .task(id: album.id) {
                                await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CassetteSpacing.m)
        }
    }

    private func errorBanner(vm: DiscoverViewModel) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack(spacing: CassetteSpacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow) // warning state — not brand accent
                Text("Unable to load Discover")
                    .font(.cassetteCellTitle)
            }
            if let message = vm.loadError?.localizedDescription {
                Text(message)
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button {
                Task { await vm.load(forceRefresh: true) }
            } label: {
                Text("Retry")
                    .font(.cassetteCellTitle)
                    .padding(.horizontal, CassetteSpacing.m)
                    .padding(.vertical, CassetteSpacing.s)
                    .background(Color.cassetteAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(CassetteSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12)) // warning state — not brand accent
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
        .padding(.horizontal, CassetteSpacing.m)
    }

    private func skeletonScroll() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CassetteSpacing.s) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                        SkeletonBlock(width: 140, height: 140, cornerRadius: CassetteCornerRadius.standard)
                        SkeletonBlock(width: 110, height: 12)
                        SkeletonBlock(width: 80, height: 10)
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, CassetteSpacing.m)
        }
        .allowsHitTesting(false)
    }

    private func emptyStateMessage(_ text: String) -> some View {
        Text(text)
            .font(.cassetteCaption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CassetteSpacing.l)
            .padding(.horizontal, CassetteSpacing.m)
    }
}
