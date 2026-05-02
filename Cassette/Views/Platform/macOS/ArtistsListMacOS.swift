// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftSonic

struct ArtistsListMacOS: View {
    @Environment(\.appContainer) private var container
    @State private var vm: ArtistListViewModel?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 24)]

    var body: some View {
        Group {
            if let vm {
                artistsContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Artists")
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
            let allArtists = vm.indexes.flatMap(\.artist)
            ScrollViewReader { proxy in
                ScrollView {
                    // TODO(v1.5.x): Add visible alphabet section headers (jump bar already implemented in v1.5)
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(allArtists) { artist in
                            NavigationLink {
                                ArtistDetailMacOS(
                                    artistId: artist.id,
                                    artistName: artist.name,
                                    coverArtId: artist.coverArt
                                )
                            } label: {
                                ArtistGridCard(artist: artist)
                            }
                            .buttonStyle(.plain)
                            .id(artist.id)
                        }
                    }
                    .padding(24)
                    .padding(.trailing, 24)
                }
                .refreshable { await vm.load() }
                .overlay(alignment: .trailing) {
                    if allArtists.count >= 30 {
                        AlphabetJumpBar(
                            availableLetters: Set(vm.indexes.map(\.name)),
                            onLetterTap: { letter in
                                if let artist = vm.indexes.first(where: { $0.name == letter })?.artist.first {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(artist.id, anchor: .top)
                                    }
                                }
                            }
                        )
                        .padding(.trailing, 8)
                    }
                }
            }
        }
    }
}

// MARK: - Artist Grid Card

private struct ArtistGridCard: View {
    let artist: ArtistID3

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: CassetteSpacing.s) {
            CoverArtView(
                id: artist.coverArt ?? artist.id,
                size: 280,
                placeholderSystemImage: "person.fill"
            )
            .frame(width: 140, height: 140)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            Text(artist.name)
                .font(.cassetteCellTitle)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if let count = artist.albumCount {
                Text("\(count) album\(count == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .onHover { isHovered = $0 }
    }
}
#endif
