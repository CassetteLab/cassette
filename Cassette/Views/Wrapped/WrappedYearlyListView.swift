// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedYearlyListView: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [WrappedYearlyPlaylist] = []
    @State private var isLoading = true

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var hasCurrentYearPlaylist: Bool {
        playlists.contains { $0.year == currentYear }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CassetteSpacing.l) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, CassetteSpacing.xxxxl)
                } else if playlists.isEmpty && hasCurrentYearPlaylist {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: CassetteSpacing.s)],
                        spacing: CassetteSpacing.s
                    ) {
                        if !hasCurrentYearPlaylist {
                            WrappedRecapMonthCard(period: .year(currentYear))
                        }
                        ForEach(playlists) { playlist in
                            WrappedYearlyCard(playlist: playlist)
                        }
                    }

                    NavigationLink {
                        WrappedView()
                    } label: {
                        HStack(spacing: CassetteSpacing.s) {
                            Image(systemName: "chart.bar.fill")
                                .font(.title2)
                                .foregroundStyle(Color.cassetteAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Listening Stats")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(.primary)
                                Text("Monthly and annual breakdowns")
                                    .font(.cassetteCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(CassetteSpacing.m)
                        .background(Color.cassetteAccent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CassetteSpacing.l)
        }
        .cassetteContentWidth()
        .navigationTitle("Wrapped")
        .task {
            guard let container,
                  let serverId = container.serverState.activeServer?.id.uuidString else {
                isLoading = false
                return
            }
            playlists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverId)
            isLoading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: CassetteSpacing.s) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(Color.cassetteAccent.opacity(0.5))
            Text("No Wrapped playlists yet.")
                .font(.cassetteCellTitle)
            Text("Your Wrapped \(currentYear) will be available on December 28.")
                .font(.cassetteCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CassetteSpacing.xxxxl)
    }
}
