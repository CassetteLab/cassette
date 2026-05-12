// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import UIKit
import WidgetKit

nonisolated struct RecentlyPlayedEntry: TimelineEntry {
    let date: Date
    let mainTrack: SharedTrackInfo?
    let subTracks: [SharedTrackInfo]
    let mainCoverImage: UIImage?
    /// Keyed by coverArtId (filename without ".jpg").
    let subCoverImages: [String: UIImage]
    /// Dominant color of mainTrack — used by small/medium backgrounds.
    let dominantColor: Color

    static var placeholder: RecentlyPlayedEntry {
        let main = SharedTrackInfo(id: "preview", title: "Track Title", artist: "Artist Name", albumID: nil, coverArtFilename: nil)
        let subs = [
            SharedTrackInfo(id: "sub1", title: "Another Track", artist: "Artist Name", albumID: nil, coverArtFilename: nil),
            SharedTrackInfo(id: "sub2", title: "Third Track",   artist: "Artist Name", albumID: nil, coverArtFilename: nil),
            SharedTrackInfo(id: "sub3", title: "Fourth Track",  artist: "Artist Name", albumID: nil, coverArtFilename: nil),
        ]
        return RecentlyPlayedEntry(date: Date(), mainTrack: main, subTracks: subs, mainCoverImage: nil, subCoverImages: [:], dominantColor: Color("CassetteAccent"))
    }

    static var empty: RecentlyPlayedEntry {
        RecentlyPlayedEntry(date: Date(), mainTrack: nil, subTracks: [], mainCoverImage: nil, subCoverImages: [:], dominantColor: Color("CassetteAccent"))
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
        guard let data = SharedStorage.defaults.data(forKey: SharedStorageKey.recentlyPlayedItems.rawValue),
              let items = try? JSONDecoder().decode([SharedTrackInfo].self, from: data),
              !items.isEmpty else {
            return .empty
        }

        let mainTrack = items[0]
        let subTracks = Array(items.dropFirst().prefix(3))

        let mainCoverArtId = mainTrack.coverArtFilename?.replacingOccurrences(of: ".jpg", with: "")
        let dominantColor = SharedWidgetData.dominantColor(forCoverArtId: mainCoverArtId)
        let mainCoverImage = mainCoverArtId.flatMap { SharedWidgetData.image(forCoverArtId: $0) }

        var subCoverImages: [String: UIImage] = [:]
        for track in subTracks {
            guard let filename = track.coverArtFilename else { continue }
            let id = filename.replacingOccurrences(of: ".jpg", with: "")
            if let image = SharedWidgetData.image(forCoverArtId: id) {
                subCoverImages[id] = image
            }
        }

        return RecentlyPlayedEntry(
            date: Date(),
            mainTrack: mainTrack,
            subTracks: subTracks,
            mainCoverImage: mainCoverImage,
            subCoverImages: subCoverImages,
            dominantColor: dominantColor
        )
    }
}
