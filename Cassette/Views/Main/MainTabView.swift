// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        TabView {
            NavigationStack {
                ArtistListView()
            }
            .tabItem { Label("Browse", systemImage: "music.note.list") }
            .safeAreaInset(edge: .bottom) {
                if container?.playerState.currentTrack != nil {
                    MiniPlayerView()
                }
            }

            NavigationStack {
                PlaylistListView()
            }
            .tabItem { Label("Playlists", systemImage: "list.bullet") }
            .safeAreaInset(edge: .bottom) {
                if container?.playerState.currentTrack != nil {
                    MiniPlayerView()
                }
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .safeAreaInset(edge: .bottom) {
                if container?.playerState.currentTrack != nil {
                    MiniPlayerView()
                }
            }
        }
    }
}
