// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container
    @State private var searchText = ""

    var body: some View {
        TabView {
            Tab("Browse", systemImage: "music.note.list") {
                NavigationStack {
                    ArtistListView()
                }
                .safeAreaInset(edge: .bottom) {
                    if container?.playerState.currentTrack != nil {
                        MiniPlayerView()
                    }
                }
            }

            Tab("Playlists", systemImage: "list.bullet") {
                NavigationStack {
                    PlaylistListView()
                }
                .safeAreaInset(edge: .bottom) {
                    if container?.playerState.currentTrack != nil {
                        MiniPlayerView()
                    }
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView()
                }
                .safeAreaInset(edge: .bottom) {
                    if container?.playerState.currentTrack != nil {
                        MiniPlayerView()
                    }
                }
            }

            Tab(role: .search) {
                NavigationStack {
                    SearchView(searchQuery: $searchText)
                        .navigationTitle("Search")
                }
                .searchable(text: $searchText, prompt: "Artists, albums, songs\u{2026}")
                .safeAreaInset(edge: .bottom) {
                    if container?.playerState.currentTrack != nil {
                        MiniPlayerView()
                    }
                }
            }
        }
    }
}
