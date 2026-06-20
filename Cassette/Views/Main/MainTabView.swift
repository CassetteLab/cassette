// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var searchPath = NavigationPath()
    @State private var homePath = NavigationPath()
    @State private var selectedTab: AppTab = .home
    @State private var showingFullPlayer = false

    private enum AppTab: Hashable { case home, discover, search }

    private var hasTrack: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    var body: some View {
        #if os(iOS)
        tabs
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                if hasTrack {
                    MiniPlayerAccessoryView(showingFullPlayer: $showingFullPlayer)
                        .environment(\.colorScheme, colorScheme)
                }
            }
            .fullScreenCover(isPresented: $showingFullPlayer) {
                FullPlayerView()
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

            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(searchQuery: $searchText, path: $searchPath)
                        .navigationTitle("Search")
                }
                .searchable(text: $searchText, prompt: "Artists, albums, songs\u{2026}")
            }
        }
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
    }
}
