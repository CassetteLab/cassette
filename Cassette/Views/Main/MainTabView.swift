// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container
    @State private var searchText = ""

    private var hasTrack: Bool {
        container?.playerState.currentTrack != nil
    }

    var body: some View {
        #if os(iOS)
        tabs
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                if hasTrack { MiniPlayerAccessoryView() }
            }
        #else
        tabs
            .safeAreaInset(edge: .bottom) {
                if hasTrack { MiniPlayerAccessoryView() }
            }
        #endif
    }

    private var tabs: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    Text("Home \u{2014} coming in 8.3")
                        .navigationTitle("Home")
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
    }
}
