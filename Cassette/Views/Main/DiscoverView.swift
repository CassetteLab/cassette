// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct DiscoverView: View {
    @Environment(\.appContainer) private var container
    @State private var vm: DiscoverViewModel?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CassetteSpacing.l) {
                if let vm {
                    recentlyPlayedSection(vm: vm)
                    mostPlayedSection(vm: vm)
                    smartShuffleSection
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
        }
        .refreshable {
            await vm?.load(forceRefresh: true)
        }
    }

    // MARK: - Sections

    private func recentlyPlayedSection(vm: DiscoverViewModel) -> some View {
        section(title: "Recently Played") {
            horizontalAlbumScroll(albums: vm.recentlyPlayed)
        }
    }

    private func mostPlayedSection(vm: DiscoverViewModel) -> some View {
        section(title: "Most Played") {
            horizontalAlbumScroll(albums: vm.mostPlayed)
        }
    }

    private var smartShuffleSection: some View {
        section(title: "Smart Shuffle") {
            Button {
                // TODO(v1.3 phase 3): wire to PlayerService.playSmartShuffle()
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
            .disabled(true)
        }
    }

    private var internetRadioSection: some View {
        section(title: "Internet Radio") {
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

    private func horizontalAlbumScroll(albums: [AlbumID3]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CassetteSpacing.s) {
                ForEach(albums, id: \.id) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CassetteSpacing.m)
        }
    }
}
