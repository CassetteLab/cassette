// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import UIKit
import WidgetKit

nonisolated struct PinnedEntry: TimelineEntry {
    let date: Date
    let items: [SharedPinnedItem]
    /// Keyed by coverArtFilename (e.g. "abc123.jpg").
    let coverImages: [String: UIImage]

    static var placeholder: PinnedEntry {
        let items = [
            SharedPinnedItem(id: "p1", kind: .album,    title: "Album Title",    subtitle: "Artist", coverArtFilename: nil),
            SharedPinnedItem(id: "p2", kind: .playlist, title: "My Playlist",    subtitle: "4 tracks", coverArtFilename: nil),
            SharedPinnedItem(id: "p3", kind: .album,    title: "Another Album",  subtitle: "Artist", coverArtFilename: nil),
            SharedPinnedItem(id: "p4", kind: .album,    title: "Fourth Item",    subtitle: "Artist", coverArtFilename: nil),
        ]
        return PinnedEntry(date: Date(), items: items, coverImages: [:])
    }

    static var empty: PinnedEntry {
        PinnedEntry(date: Date(), items: [], coverImages: [:])
    }
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> PinnedEntry {
        guard let data = SharedStorage.defaults.data(forKey: SharedStorageKey.pinnedItems.rawValue),
              let items = try? JSONDecoder().decode([SharedPinnedItem].self, from: data),
              !items.isEmpty else {
            return .empty
        }

        var coverImages: [String: UIImage] = [:]
        for item in items {
            guard let filename = item.coverArtFilename else { continue }
            let id = filename.replacingOccurrences(of: ".jpg", with: "")
            if let image = SharedWidgetData.image(forCoverArtId: id) {
                coverImages[filename] = image
            }
        }

        return PinnedEntry(date: Date(), items: items, coverImages: coverImages)
    }
}
#endif
