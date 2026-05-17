// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import OSLog

struct WrappedView: View {
    @Environment(\.appContainer) private var container
    @State private var selectedPeriod: WrappedPeriod = .currentMonth()
    @State private var data: WrappedData?
    @State private var isLoading = true
    @State private var wrappedPlaylistId: String?
    @State private var appeared = false
    @State private var loadFailed = false
    #if DEBUG
    @State private var overrideWithFakeData = false
    #endif

    init(initialPeriod: WrappedPeriod = .currentMonth()) {
        _selectedPeriod = State(initialValue: initialPeriod)
    }

    private var availablePeriods: [WrappedPeriod] {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        var periods: [WrappedPeriod] = (1...month).map { .month(year: year, month: $0) }
        periods.append(.year(year))
        return periods
    }

    private var currentYear: Int {
        switch selectedPeriod {
        case .month(let year, _): return year
        case .year(let year): return year
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CassetteSpacing.xl) {
                WrappedPeriodPicker(selectedPeriod: $selectedPeriod, availablePeriods: availablePeriods)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, CassetteSpacing.xxxxl)
                } else if loadFailed {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Recap",
                        subtitle: "Something went wrong. Pull to refresh.",
                        action: .init(label: "Retry") { Task { await loadData() } }
                    )
                } else if let d = data, d.totalTracksPlayed > 0 {
                    WrappedStatHero(data: d)
                        .cascadeAppear(order: 0, trigger: appeared)
                    WrappedTopArtistsSection(artists: d.topArtists)
                        .cascadeAppear(order: 1, trigger: appeared)
                    WrappedTopTracksSection(tracks: d.topTracks)
                        .cascadeAppear(order: 2, trigger: appeared)
                    WrappedTopAlbumsSection(albums: d.topAlbums)
                        .cascadeAppear(order: 3, trigger: appeared)
                    WrappedAwardsSection(data: d)
                        .cascadeAppear(order: 4, trigger: appeared)
                    if case .year = selectedPeriod {
                        WrappedYearCard(
                            year: currentYear,
                            firstTrack: d.firstTrackOfPeriod,
                            lastTrack: d.lastTrackOfPeriod,
                            playlistId: wrappedPlaylistId
                        )
                        .cascadeAppear(order: 5, trigger: appeared)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.l)
            .padding(.bottom, CassetteSpacing.xl)
        }
        .refreshable { await loadData() }
        .cassetteContentWidth()
        .navigationTitle("")
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Fake Month Data") {
                        overrideWithFakeData = true
                        injectFakeData(period: selectedPeriod)
                    }
                    Button("Fake Year Data") {
                        overrideWithFakeData = true
                        selectedPeriod = .year(2026)
                        injectFakeData(period: .year(2026))
                    }
                    Divider()
                    Button("Reset to Real Data") {
                        overrideWithFakeData = false
                        Task { await loadData() }
                    }
                    .disabled(!overrideWithFakeData)
                } label: {
                    Image(systemName: "flask")
                        .foregroundStyle(overrideWithFakeData ? Color.cassetteAccent : Color.primary)
                }
            }
            #endif
        }
        .task(id: selectedPeriod) {
            await loadData()
        }
        .background {
            if let serverId = container?.serverState.activeServer?.id.uuidString {
                PlaybackEventWatcher(serverId: serverId) {
                    Task { await refreshData() }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: CassetteSpacing.s) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(Color.cassetteAccent.opacity(0.5))
            Text("No listens for this period.")
                .font(.cassetteCellTitle)
            Text("Listen up — we'll keep track of your activity.")
                .font(.cassetteCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CassetteSpacing.xxxxl)
    }

    // MARK: - Data loading

    private func refreshData() async {
        #if DEBUG
        guard !overrideWithFakeData else { return }
        #endif
        guard let container, let serverId = container.serverState.activeServer?.id.uuidString else { return }
        let result = await container.statsService.wrappedData(for: selectedPeriod, serverId: serverId, calendar: .current)
        guard !Task.isCancelled else { return }
        data = result
    }

    private func loadData() async {
        #if DEBUG
        guard !overrideWithFakeData else { return }
        #endif
        loadFailed = false
        guard let container, let serverId = container.serverState.activeServer?.id.uuidString else {
            isLoading = false
            loadFailed = true
            return
        }
        Logger.wrapped.debug("[WRAPPED-VIEW] fetch start period=\(selectedPeriod.displayName, privacy: .public)")
        appeared = false
        isLoading = true
        data = nil
        wrappedPlaylistId = nil
        let result = await container.statsService.wrappedData(
            for: selectedPeriod, serverId: serverId, calendar: .current
        )
        guard !Task.isCancelled else { return }
        if case .year(let y) = selectedPeriod {
            wrappedPlaylistId = await container.wrappedPlaylistService.playlistId(year: y, serverId: serverId)
        }
        data = result
        isLoading = false
        appeared = true
        Logger.wrapped.debug("[WRAPPED-VIEW] fetch done totalPlays=\(result.totalTracksPlayed, privacy: .public)")
    }
}

// MARK: - Debug fake data

#if DEBUG
extension WrappedView {
    private func injectFakeData(period: WrappedPeriod) {
        let firstTrack = TopTrackEntry(
            rank: 0, trackId: "dbg-t1",
            title: "Midnight City", artistName: "M83",
            albumTitle: "Hurry Up, We're Dreaming",
            totalSecondsListened: 244, playCount: 1
        )
        let lastTrack = TopTrackEntry(
            rank: 0, trackId: "dbg-t3",
            title: "Instant Crush", artistName: "Daft Punk",
            albumTitle: "Random Access Memories",
            totalSecondsListened: 337, playCount: 1
        )
        let fake = WrappedData(
            period: period,
            serverId: "debug-server",
            generatedAt: Date(),
            totalSecondsListened: 25_920,
            totalTracksPlayed: 148,
            totalUniqueTracks: 63,
            totalUniqueArtists: 12,
            totalUniqueAlbums: 19,
            topTracks: [
                TopTrackEntry(rank: 1, trackId: "dbg-t1", title: "Midnight City",     artistName: "M83",        albumTitle: "Hurry Up, We're Dreaming",   totalSecondsListened: 1_440, playCount: 18),
                TopTrackEntry(rank: 2, trackId: "dbg-t2", title: "Digital Love",      artistName: "Daft Punk",  albumTitle: "Discovery",                  totalSecondsListened: 1_200, playCount: 14),
                TopTrackEntry(rank: 3, trackId: "dbg-t3", title: "Instant Crush",     artistName: "Daft Punk",  albumTitle: "Random Access Memories",      totalSecondsListened: 960,   playCount: 11),
                TopTrackEntry(rank: 4, trackId: "dbg-t4", title: "Girl",              artistName: "Beck",       albumTitle: "Sea Change",                 totalSecondsListened: 820,   playCount: 9),
                TopTrackEntry(rank: 5, trackId: "dbg-t5", title: "Blue (Da Ba Dee)",  artistName: "Eiffel 65",  albumTitle: "Europop",                    totalSecondsListened: 700,   playCount: 8),
            ],
            topAlbums: [
                TopAlbumEntry(rank: 1, albumId: "dbg-a1", title: "Random Access Memories",       artistName: "Daft Punk", totalSecondsListened: 5_400, playCount: 32, uniqueTracks: 13),
                TopAlbumEntry(rank: 2, albumId: "dbg-a2", title: "Discovery",                    artistName: "Daft Punk", totalSecondsListened: 3_600, playCount: 22, uniqueTracks: 14),
                TopAlbumEntry(rank: 3, albumId: "dbg-a3", title: "Hurry Up, We're Dreaming",     artistName: "M83",       totalSecondsListened: 2_880, playCount: 18, uniqueTracks: 11),
                TopAlbumEntry(rank: 4, albumId: "dbg-a4", title: "Sea Change",                   artistName: "Beck",      totalSecondsListened: 2_100, playCount: 13, uniqueTracks: 10),
                TopAlbumEntry(rank: 5, albumId: "dbg-a5", title: "Europop",                      artistName: "Eiffel 65", totalSecondsListened: 1_440, playCount: 10, uniqueTracks: 7),
            ],
            topArtists: [
                TopArtistEntry(rank: 1, artistId: "dbg-ar1", name: "Daft Punk", totalSecondsListened: 9_000, playCount: 54, uniqueTracks: 22),
                TopArtistEntry(rank: 2, artistId: "dbg-ar2", name: "M83",       totalSecondsListened: 4_500, playCount: 28, uniqueTracks: 14),
                TopArtistEntry(rank: 3, artistId: "dbg-ar3", name: "Beck",      totalSecondsListened: 3_240, playCount: 20, uniqueTracks: 12),
                TopArtistEntry(rank: 4, artistId: "dbg-ar4", name: "Eiffel 65", totalSecondsListened: 2_160, playCount: 14, uniqueTracks: 8),
                TopArtistEntry(rank: 5, artistId: "dbg-ar5", name: "Air",       totalSecondsListened: 1_800, playCount: 11, uniqueTracks: 7),
            ],
            dominantGenre: "Electronic",
            streakDays: 21,
            firstTrackOfPeriod: firstTrack,
            lastTrackOfPeriod: lastTrack
        )
        data = fake
        isLoading = false
        loadFailed = false
        if case .year = period {
            wrappedPlaylistId = "debug-playlist-2026"
        }
        appeared = true
    }
}
#endif

// MARK: - Cascade appear modifier

private extension View {
    func cascadeAppear(order: Int, trigger: Bool) -> some View {
        self
            .opacity(trigger ? 1 : 0)
            .offset(y: trigger ? 0 : 16)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82).delay(Double(order) * 0.07),
                value: trigger
            )
    }
}

// MARK: - Server-scoped playback event watcher

private struct PlaybackEventWatcher: View {
    let onCountChange: () -> Void
    @Query private var events: [PlaybackEvent]

    init(serverId: String, onCountChange: @escaping () -> Void) {
        self.onCountChange = onCountChange
        let sid = serverId
        _events = Query(filter: #Predicate<PlaybackEvent> { $0.serverId == sid })
    }

    var body: some View {
        Color.clear
            .onChange(of: events.count) { _, _ in onCountChange() }
    }
}
