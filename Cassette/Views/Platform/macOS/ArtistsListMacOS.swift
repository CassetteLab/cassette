// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftSonic

struct ArtistsListMacOS: View {
    @Environment(\.appContainer) private var container
    @State private var vm: ArtistListViewModel?
    @AppStorage("cassette.artistSort") private var artistSort: ArtistSort = .name

    var body: some View {
        Group {
            if let vm {
                artistsContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Artists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ArtistSortMenu(sort: $artistSort)
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if vm == nil { vm = ArtistListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await vm?.load()
        }
    }

    @ViewBuilder
    private func artistsContent(_ vm: ArtistListViewModel) -> some View {
        if vm.isLoading && vm.indexes.isEmpty {
            LoadingStateView()
        } else if let error = vm.error, vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artists",
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No Artists",
                subtitle: "Your library appears to be empty."
            )
        } else {
            let allArtists = artistSort.sorted(vm.indexes.flatMap(\.artist))
            GeometryReader { geo in
                let count = Self.gridColumnCount(for: geo.size.width)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: count)
                ScrollViewReader { proxy in
                    ScrollView {
                        // TODO(v1.5.x): Add visible alphabet section headers (jump bar already implemented in v1.5)
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(allArtists) { artist in
                                NavigationLink(value: HomeDestination.artist(artist)) {
                                    ArtistGridCard(artist: artist)
                                }
                                .buttonStyle(.plain)
                                .id(artist.id)
                            }
                        }
                        .padding(24)
                    }
                    .refreshable { await vm.load() }
                }
            }
        }
    }
    private static func gridColumnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<900:  return 3
        case ..<1200: return 4
        case ..<1600: return 5
        default:      return 6
        }
    }
}
#endif
