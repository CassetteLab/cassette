// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct RadioListView: View {
    @Environment(\.appContainer) private var container
    @State private var stations: [InternetRadioStation] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading && stations.isEmpty {
                LoadingStateView()
            } else if let error, stations.isEmpty {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to Load Radios",
                    subtitle: error.localizedDescription,
                    action: .init(label: "Retry") { Task { await load(forceRefresh: true) } }
                )
            } else if stations.isEmpty {
                EmptyStateView(
                    systemImage: "antenna.radiowaves.left.and.right",
                    title: "No Radio Stations",
                    subtitle: "No internet radio stations are configured on this server."
                )
            } else {
                List(stations, id: \.id) { station in
                    Button {
                        Task { await play(station) }
                    } label: {
                        RadioStationRow(station: station)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .refreshable { await load(forceRefresh: true) }
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Radio")
        .task(id: container?.serverState.isOnline) {
            guard container?.serverState.isOnline == true else { return }
            await load(forceRefresh: false)
        }
    }

    private func load(forceRefresh: Bool) async {
        guard let radioService = container?.radioService else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            stations = try await radioService.listStations(forceRefresh: forceRefresh)
            error = nil
        } catch {
            self.error = error
        }
    }

    private func play(_ station: InternetRadioStation) async {
        guard let playerService = container?.playerService else { return }
        HapticFeedback.medium.trigger()
        do {
            try await playerService.playRadio(station)
        } catch {
            // Playback errors surface via the existing error infrastructure in a later commit.
        }
    }
}

// MARK: - Row

private struct RadioStationRow: View {
    let station: InternetRadioStation

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            if let coverArt = station.coverArt, !coverArt.isEmpty {
                CoverArtCard(id: coverArt, size: 56)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous)
                        .fill(Color.cassetteAccent.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Color.cassetteAccent)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let homePageUrl = station.homePageUrl, !homePageUrl.isEmpty {
                    Text(homePageUrl)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.cassetteAccent)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
    }
}
