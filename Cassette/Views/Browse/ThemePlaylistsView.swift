// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct ThemePlaylistsView: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [ThemePlaylistType: ThemePlaylistDTO] = [:]
    @State private var isSyncing = false
    @State private var userPlaylists: [Playlist] = []
    @State private var isLoadingPlaylists = false
    @Namespace private var forYouNamespace
    @Namespace private var userPlaylistsNamespace

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CassetteSpacing.l) {
                forYouSection
                yourPlaylistsSection
            }
            .padding(.vertical, CassetteSpacing.m)
        }
        .cassetteContentWidth()
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        Task { await sync() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(container?.serverState.isOnline != true)
                }
            }
        }
        .task {
            await loadCached()
            await loadUserPlaylists()
            guard container?.serverState.isOnline == true else { return }
            await sync()
        }
        .refreshable {
            await loadUserPlaylists()
            await sync()
        }
    }

    // MARK: - For You section

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("For You")
                .font(.cassetteSectionTitle)
                .padding(.horizontal, CassetteSpacing.m)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CassetteSpacing.s) {
                    ForEach(ThemePlaylistType.allCases, id: \.self) { type in
                        if let dto = playlists[type] {
                            NavigationLink {
                                ThemePlaylistDetailView(dto: dto)
                                    .cassetteZoomTransition(sourceID: dto.id, in: forYouNamespace)
                            } label: {
                                ThemePlaylistCard(type: type, dto: dto, namespace: forYouNamespace)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ThemePlaylistCard(type: type, dto: nil, namespace: forYouNamespace)
                        }
                    }
                }
                .padding(.horizontal, CassetteSpacing.m)
            }
        }
    }

    // MARK: - Your Playlists section

    @ViewBuilder
    private var yourPlaylistsSection: some View {
        if !userPlaylists.isEmpty || isLoadingPlaylists {
            VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                Text("Your Playlists")
                    .font(.cassetteSectionTitle)
                    .padding(.horizontal, CassetteSpacing.m)

                if isLoadingPlaylists && userPlaylists.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        skeletonPlaylistRow
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(userPlaylists) { playlist in
                            NavigationLink {
                                #if os(macOS)
                                PlaylistDetailMacOS(playlistId: playlist.id, name: playlist.name, coverArtId: playlist.coverArt)
                                #else
                                PlaylistDetailView(
                                    playlist: playlist,
                                    zoomSourceId: playlist.id,
                                    zoomNamespace: userPlaylistsNamespace
                                )
                                #endif
                            } label: {
                                UserPlaylistRow(playlist: playlist, namespace: userPlaylistsNamespace)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, CassetteSpacing.m + 56 + CassetteSpacing.m)
                        }
                    }
                }
            }
        }
    }

    private var skeletonPlaylistRow: some View {
        HStack(spacing: CassetteSpacing.m) {
            SkeletonBlock(width: 56, height: 56, cornerRadius: CassetteCornerRadius.standard)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 140, height: 12)
                SkeletonBlock(width: 80, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.xs)
    }

    // MARK: - Actions

    private func loadCached() async {
        guard let service = container?.themePlaylistService,
              let serverId = container?.serverState.activeServer?.id.uuidString else { return }
        let dtos = await service.loadCached(serverId: serverId)
        playlists = Dictionary(uniqueKeysWithValues: dtos.map { ($0.type, $0) })
    }

    private func loadUserPlaylists() async {
        guard let playlistService = container?.playlistService else { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        userPlaylists = (try? await playlistService.listPlaylists()) ?? []
    }

    private func sync() async {
        guard let service = container?.themePlaylistService,
              let serverId = container?.serverState.activeServer?.id.uuidString else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await service.sync(serverId: serverId)
            await loadCached()
        } catch {}
    }
}

// MARK: - ThemePlaylistCard

private struct ThemePlaylistCard: View {
    let type: ThemePlaylistType
    let dto: ThemePlaylistDTO?
    let namespace: Namespace.ID

    private static let cardSize: CGFloat = 140
    // 2px gap between cells: (140 - 2) / 2 = 69
    private static let cellSize: CGFloat = 69
    private static let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            artworkView
                .frame(width: Self.cardSize, height: Self.cardSize)
                .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
                .modifier(ConditionalMatchedTransitionSource(id: dto?.id ?? type.rawValue, namespace: namespace))

            Text(type.displayName)
                .font(.cassetteCaption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let dto, dto.trackCount > 0 {
                Text("\(dto.trackCount) tracks")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Not generated yet")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.cardSize)
        .opacity(dto == nil ? 0.5 : 1)
    }

    @ViewBuilder
    private var artworkView: some View {
        let ids = Array((dto?.trackIds ?? []).prefix(4))
        if ids.count >= 4 {
            VStack(spacing: Self.gap) {
                HStack(spacing: Self.gap) {
                    quadCell(id: ids[0])
                    quadCell(id: ids[1])
                }
                HStack(spacing: Self.gap) {
                    quadCell(id: ids[2])
                    quadCell(id: ids[3])
                }
            }
        } else {
            ZStack {
                CassetteColors.accentBackground
                Image(systemName: "music.note.list")
                    .font(.title)
                    .foregroundStyle(CassetteColors.accent)
            }
        }
    }

    private func quadCell(id: String) -> some View {
        CoverArtView(id: id, size: Int(Self.cellSize * 2), cornerRadius: 0)
            .frame(width: Self.cellSize, height: Self.cellSize)
            .clipped()
    }
}

// MARK: - UserPlaylistRow

private struct UserPlaylistRow: View {
    let playlist: Playlist
    let namespace: Namespace.ID

    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: playlist.coverArt ?? playlist.id, size: 56, initialImage: coverImage)
                .modifier(ConditionalMatchedTransitionSource(id: playlist.id, namespace: namespace))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(playlist.songCount) track\(playlist.songCount == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
        .task(id: playlist.id) {
            coverImage = await artworkImageCache.load(coverArtId: playlist.coverArt ?? playlist.id)
        }
    }
}

// MARK: - Zoom transition source modifier
// TODO(refactor): extract ConditionalMatchedTransitionSource to a shared modifier (duplicated in HomeView, DiscoverView)

private struct ConditionalMatchedTransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
