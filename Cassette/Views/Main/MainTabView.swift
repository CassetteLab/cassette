// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Text("Browse")
                .tabItem { Label("Browse", systemImage: "music.note.list") }

            Text("Playlists")
                .tabItem { Label("Playlists", systemImage: "list.bullet") }

            // TODO(v1.0): add "About" screen in Settings with license info and third-party attributions (SwiftSonic MIT)
            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
