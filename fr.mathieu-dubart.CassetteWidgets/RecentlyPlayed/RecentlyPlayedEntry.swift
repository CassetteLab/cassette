// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import UIKit
import WidgetKit

nonisolated struct RecentlyPlayedEntry: TimelineEntry {
    let date: Date
    let track: SharedTrackInfo?
    let dominantColor: Color
    let coverImage: UIImage?

    static var placeholder: RecentlyPlayedEntry {
        RecentlyPlayedEntry(
            date: Date(),
            track: SharedTrackInfo(id: "preview", title: "Track Title", artist: "Artist Name", albumID: nil, coverArtFilename: nil),
            dominantColor: Color("CassetteAccent"),
            coverImage: nil
        )
    }

    static var empty: RecentlyPlayedEntry {
        RecentlyPlayedEntry(date: Date(), track: nil, dominantColor: Color("CassetteAccent"), coverImage: nil)
    }
}

struct RecentlyPlayedProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentlyPlayedEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentlyPlayedEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentlyPlayedEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> RecentlyPlayedEntry {
        guard let track = SharedWidgetData.latestRecentlyPlayed() else {
            return .empty
        }
        let coverArtId = track.coverArtFilename?.replacingOccurrences(of: ".jpg", with: "")
        let color = SharedWidgetData.dominantColor(forCoverArtId: coverArtId)
        let image = coverArtId.flatMap { SharedWidgetData.image(forCoverArtId: $0) }
        return RecentlyPlayedEntry(date: Date(), track: track, dominantColor: color, coverImage: image)
    }
}
