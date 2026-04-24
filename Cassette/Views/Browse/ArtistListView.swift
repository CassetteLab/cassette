// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct ArtistListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Browse")
        .task {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = ArtistListViewModel(libraryService: svc) }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: ArtistListViewModel) -> some View {
        if vm.isLoading && vm.indexes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.indexes.isEmpty {
            ContentUnavailableView(
                "Unable to load artists",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else {
            List(vm.indexes, id: \.name) { index in
                Section(index.name) {
                    ForEach(index.artist) { artist in
                        NavigationLink(value: artist) {
                            HStack(spacing: 12) {
                                CoverArtView(id: artist.coverArt ?? artist.id, size: 44)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                    if let count = artist.albumCount {
                                        Text("\(count) album\(count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: ArtistID3.self) { artist in
                ArtistDetailView(artist: artist)
            }
        }
    }
}
