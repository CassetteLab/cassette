import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Text("Browse")
                .tabItem { Label("Browse", systemImage: "music.note.list") }

            Text("Playlists")
                .tabItem { Label("Playlists", systemImage: "list.bullet") }

            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
