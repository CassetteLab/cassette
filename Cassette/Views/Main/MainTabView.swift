// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container
    @State private var searchText = ""
    @State private var showingFullPlayer = false

    private var hasTrack: Bool {
        container?.playerState.currentTrack != nil
    }

    var body: some View {
        #if os(iOS)
        tabs
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                if hasTrack { MiniPlayerAccessoryView(showingFullPlayer: $showingFullPlayer) }
            }
            .sheet(isPresented: $showingFullPlayer) {
                FullPlayerView(isPresented: $showingFullPlayer)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
            }
        #else
        tabs
            .safeAreaInset(edge: .bottom) {
                if hasTrack { MiniPlayerAccessoryView(showingFullPlayer: $showingFullPlayer) }
            }
            .fullScreenCover(isPresented: $showingFullPlayer) {
                FullPlayerView(isPresented: $showingFullPlayer)
            }
        #endif
    }

    private var tabs: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    HomeView()
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView()
                }
            }

            Tab(role: .search) {
                NavigationStack {
                    SearchView(searchQuery: $searchText)
                        .navigationTitle("Search")
                }
                .searchable(text: $searchText, prompt: "Artists, albums, songs\u{2026}")
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard container?.serverState.isOnline == true else { return }
            try? await container?.favoritesService.syncFromServer()
        }
    }
}
