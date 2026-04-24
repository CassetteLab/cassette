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
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artists",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No Artists",
                subtitle: "Your library appears to be empty."
            )
        } else {
            List(vm.indexes, id: \.name) { index in
                Section(index.name) {
                    ForEach(index.artist) { artist in
                        NavigationLink(value: artist) {
                            ArtistRow(artist: artist)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
            .navigationDestination(for: ArtistID3.self) { artist in
                ArtistDetailView(artist: artist)
            }
        }
    }
}
