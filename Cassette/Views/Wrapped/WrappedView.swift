// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
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
                        Task { await injectFakeData(period: selectedPeriod) }
                    }
                    Button("Fake Year Data") {
                        overrideWithFakeData = true
                        selectedPeriod = .year(2026)
                        Task { await injectFakeData(period: .year(2026)) }
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
    private func injectFakeData(period: WrappedPeriod) async {
        guard let container else { return }
        isLoading = true

        async let songsTask = try? container.libraryService.randomSongs(size: 20)
        async let albumsTask = try? container.libraryService.recentlyAddedAlbums(size: 10)
        let (songs, albums) = await (songsTask, albumsTask)

        guard let songs, !songs.isEmpty else {
            isLoading = false
            container.toastService.showError("Debug: no tracks — connect to your server first.")
            return
        }

        let topTracks: [TopTrackEntry] = songs.prefix(5).enumerated().map { i, song in
            TopTrackEntry(
                rank: i + 1,
                trackId: song.id,
                title: song.title,
                artistName: song.artist ?? "Unknown Artist",
                albumTitle: song.album,
                totalSecondsListened: TimeInterval((5 - i) * 480),
                playCount: 20 - i * 3
            )
        }

        let topAlbums: [TopAlbumEntry] = (albums ?? []).prefix(5).enumerated().map { i, album in
            TopAlbumEntry(
                rank: i + 1,
                albumId: album.id,
                title: album.name,
                artistName: album.artist ?? "Unknown Artist",
                totalSecondsListened: TimeInterval((5 - i) * 1_200),
                playCount: 30 - i * 4,
                uniqueTracks: 10 - i
            )
        }

        var seenArtistIds = Set<String>()
        var topArtists: [TopArtistEntry] = []
        for song in songs where topArtists.count < 5 {
            guard let artistId = song.artistId, let artistName = song.artist,
                  !seenArtistIds.contains(artistId) else { continue }
            seenArtistIds.insert(artistId)
            let rank = topArtists.count + 1
            topArtists.append(TopArtistEntry(
                rank: rank,
                artistId: artistId,
                name: artistName,
                totalSecondsListened: TimeInterval((5 - rank + 1) * 2_400),
                playCount: 50 - rank * 8,
                uniqueTracks: 15 - rank * 2
            ))
        }

        let makeFirstLast = { (t: TopTrackEntry) in
            TopTrackEntry(rank: 0, trackId: t.trackId, title: t.title,
                          artistName: t.artistName, albumTitle: t.albumTitle,
                          totalSecondsListened: 0, playCount: 1)
        }

        let fake = WrappedData(
            period: period,
            serverId: container.serverState.activeServer?.id.uuidString ?? "debug",
            generatedAt: Date(),
            totalSecondsListened: 25_920,
            totalTracksPlayed: 148,
            totalUniqueTracks: 63,
            totalUniqueArtists: topArtists.count,
            totalUniqueAlbums: topAlbums.count,
            topTracks: topTracks,
            topAlbums: topAlbums,
            topArtists: topArtists,
            dominantGenre: songs.compactMap(\.genre).first ?? "Unknown",
            streakDays: 21,
            firstTrackOfPeriod: topTracks.first.map(makeFirstLast),
            lastTrackOfPeriod: topTracks.last.map(makeFirstLast)
        )

        data = fake
        isLoading = false
        loadFailed = false
        if case .year = period { wrappedPlaylistId = "debug-playlist" }
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
