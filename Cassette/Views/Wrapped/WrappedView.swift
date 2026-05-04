// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

struct WrappedView: View {
    @Environment(\.appContainer) private var container
    @State private var selectedPeriod: WrappedPeriod = .currentMonth()
    @State private var data: WrappedData?
    @State private var isLoading = true
    @State private var wrappedPlaylistId: String?

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
                } else if let d = data, d.totalTracksPlayed > 0 {
                    WrappedStatHero(data: d)
                    WrappedTopArtistsSection(artists: d.topArtists)
                    WrappedTopTracksSection(tracks: d.topTracks)
                    WrappedTopAlbumsSection(albums: d.topAlbums)
                    WrappedRewardsSection(data: d)
                    if case .year = selectedPeriod {
                        WrappedYearCard(
                            year: currentYear,
                            firstTrack: d.firstTrackOfPeriod,
                            lastTrack: d.lastTrackOfPeriod,
                            playlistId: wrappedPlaylistId
                        )
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.m)
            .padding(.bottom, CassetteSpacing.xl)
        }
        .cassetteContentWidth()
        .navigationTitle("Wrapped")
        .task(id: selectedPeriod) {
            await loadData()
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

    private func loadData() async {
        guard let container, let serverId = container.serverState.activeServer?.id.uuidString else {
            isLoading = false
            return
        }
        Logger.wrapped.debug("[WRAPPED-VIEW] fetch start period=\(selectedPeriod.displayName, privacy: .public)")
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
        Logger.wrapped.debug("[WRAPPED-VIEW] fetch done totalPlays=\(result.totalTracksPlayed, privacy: .public)")
    }
}
