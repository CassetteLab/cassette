// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct LyricsView: View {
    let song: DisplayableSong?

    @Environment(\.appContainer) private var container
    @State private var lyrics: Lyrics?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let text = lyrics?.value {
                    ScrollView {
                        Text(text)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(CassetteSpacing.l)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "quote.bubble",
                        title: "No Lyrics",
                        subtitle: "Lyrics are not available for this track."
                    )
                }
            }
            .navigationTitle(song?.title ?? "Lyrics")
            .navigationBarTitleDisplayModeInline()
        }
        .task(id: song?.id) {
            await loadLyrics()
        }
    }

    private func loadLyrics() async {
        guard let song else {
            lyrics = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        lyrics = try? await container?.libraryService.lyrics(artist: song.artist, title: song.title)
    }
}
