// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct DiscoverView: View {
    @Environment(\.appContainer) private var container
    @State private var vm: DiscoverViewModel?
    @Namespace private var recentlyPlayedNS
    @Namespace private var mostPlayedNS
    @State private var yearlyPlaylists: [WrappedYearlyPlaylist] = []
    @State private var radioStations: [InternetRadioStation] = []
    @State private var showStoryPlayer = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CassetteSpacing.l) {
                if let vm {
                    if vm.isErrorState {
                        errorBanner(vm: vm)
                    } else {
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
                vm = DiscoverViewModel(libraryService: container.libraryService)
            }
            await vm?.load()
            guard let serverId = container.serverState.activeServer?.id.uuidString else { return }
            yearlyPlaylists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverId)
            radioStations = (try? await container.radioService.listStations(forceRefresh: false)) ?? []
        }
        .refreshable {
            await vm?.load(forceRefresh: true)
        }
        .fullScreenCover(isPresented: $showStoryPlayer) {
            WrappedStoryPlayerView(year: Calendar.current.component(.year, from: Date()))
        }
    }

    // MARK: - Sections

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
                // TODO: remove before release — dev entry point for story player
                Button {
                    showStoryPlayer = true
                } label: {
                    Text("▶ Story")
                        .font(.cassetteCaption)
                        .foregroundStyle(Color.cassetteAccent)
                }
                .buttonStyle(.plain)
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
                    ForEach(wrappedCardPeriods, id: \.self) { period in
                        WrappedRecapMonthCard(period: period)
                    }
                }
                .padding(.horizontal, CassetteSpacing.m)
            }
        }
    }

    private var wrappedCardPeriods: [WrappedPeriod] {
        let year = Calendar.current.component(.year, from: Date())
return yearlyPlaylists.contains { $0.year == year } ? [] : [.year(year)]
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
                        AlbumDetailView(album: album, zoomSourceId: album.id, zoomNamespace: namespace)
                        #endif
                    } label: {
                        AlbumCard(album: album)
                            .modifier(ConditionalMatchedTransitionSource(id: album.id, namespace: namespace))
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
                    .foregroundStyle(.orange)
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
        .background(Color.orange.opacity(0.08))
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

// MARK: - Zoom transition source modifier

private struct ConditionalMatchedTransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
