// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var searchPath = NavigationPath()
    @State private var homePath = NavigationPath()
    @State private var selectedTab: AppTab = .home
    @State private var showingFullPlayer = false
    @Namespace private var playerZoom
    private let fullPlayerZoomID = "full-player"

    private enum AppTab: Hashable {
        case home, discover, search
        case playlists, albums, artists, songs, favorites, downloads
    }

    private var hasTrack: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            tabs
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if hasTrack {
                        MiniPlayerAccessoryView(showingFullPlayer: $showingFullPlayer)
                            .environment(\.colorScheme, colorScheme)
                            .cassetteMatchedTransitionSource(id: fullPlayerZoomID, in: playerZoom)
                    }
                }
                .fullScreenCover(isPresented: $showingFullPlayer) {
                    FullPlayerView()
                        .cassetteZoomTransition(sourceID: fullPlayerZoomID, in: playerZoom)
                }
        } else {
            // iOS 18: no tabViewBottomAccessory API. Float the mini player above the
            // tab bar via a bottom safe-area inset, supplying the material background
            // the accessory container would otherwise provide (glass falls back to
            // .ultraThinMaterial pre-26). The zoom transition stays — it's iOS 18+.
            tabs
                .safeAreaInset(edge: .bottom) {
                    if hasTrack {
                        MiniPlayerAccessoryView(showingFullPlayer: $showingFullPlayer)
                            .environment(\.colorScheme, colorScheme)
                            .cassetteMatchedTransitionSource(id: fullPlayerZoomID, in: playerZoom)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                            .overlay {
                                RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                            .padding(.horizontal, CassetteSpacing.s)
                            // Lift clear of the tab bar (safeAreaInset draws over it), plus a small gap.
                            .padding(.bottom, horizontalSizeClass == .compact
                                     ? CassetteSpacing.legacyTabBarHeight + CassetteSpacing.xs
                                     : CassetteSpacing.xs)
                    }
                }
                .fullScreenCover(isPresented: $showingFullPlayer) {
                    FullPlayerView()
                        .cassetteZoomTransition(sourceID: fullPlayerZoomID, in: playerZoom)
                }
        }
        #else
        tabs
            .safeAreaInset(edge: .bottom) {
                if hasTrack { MiniPlayerAccessoryView(showingFullPlayer: $showingFullPlayer) }
            }
            .sheet(isPresented: $showingFullPlayer) {
                FullPlayerView()
            }
        #endif
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView()
                }
            }

            Tab("Discover", systemImage: "sparkles", value: AppTab.discover) {
                NavigationStack {
                    DiscoverView()
                }
            }

            #if os(iOS)
            TabSection("Library") {
                Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                    LibraryNavigationView(destination: .libraryPlaylists)
                }
                Tab("Albums", systemImage: "square.stack", value: AppTab.albums) {
                    LibraryNavigationView(destination: .libraryAlbums)
                }
                Tab("Artists", systemImage: "music.mic", value: AppTab.artists) {
                    LibraryNavigationView(destination: .libraryArtists)
                }
                Tab("Songs", systemImage: "music.note", value: AppTab.songs) {
                    LibraryNavigationView(destination: .librarySongs)
                }
                Tab("Favorites", systemImage: "star.fill", value: AppTab.favorites) {
                    LibraryNavigationView(destination: .libraryFavorites)
                }
                Tab("Downloads", systemImage: "arrow.down.circle.fill", value: AppTab.downloads) {
                    LibraryNavigationView(destination: .libraryDownloads)
                }
            }
            .defaultVisibility(.hidden, for: .tabBar)
            #endif

            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(searchQuery: $searchText, path: $searchPath)
                        .navigationTitle("Search")
                }
                .searchable(text: $searchText, prompt: "Artists, albums, songs\u{2026}")
            }
        }
        #if os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.sidebar)
        #endif
        .accentColor(.cassetteAccent)

        .task(id: container?.serverState.isOnline) {
            guard container?.serverState.isOnline == true else { return }
            try? await container?.favoritesService.syncFromServer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToArtist)) { note in
            guard let id   = note.userInfo?["artistId"]   as? String,
                  let name = note.userInfo?["artistName"] as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            showingFullPlayer = false
            selectedTab = .home
            homePath.append(HomeDestination.artistById(id: id, name: name, coverArtId: coverArtId))
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToPlaylist)) { note in
            guard let id   = note.userInfo?["playlistId"] as? String,
                  let name = note.userInfo?["name"]       as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            showingFullPlayer = false
            selectedTab = .home
            homePath.append(HomeDestination.playlistById(id: id, name: name, coverArtId: coverArtId, hasZoomSource: false))
        }
    }
}

#if os(iOS)
private struct LibraryNavigationView: View {
    let destination: HomeDestination
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeDestinationView(destination: destination)
                .navigationDestination(for: HomeDestination.self) { destination in
                    HomeDestinationView(destination: destination)
                }
        }
    }
}
#endif
