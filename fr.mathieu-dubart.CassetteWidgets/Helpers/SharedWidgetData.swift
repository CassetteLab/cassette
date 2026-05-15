// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import UIKit
import WidgetKit

enum SharedWidgetData {
    /// Loads a UIImage from the shared container's CoverArt directory.
    /// Returns nil if the file doesn't exist or fails to decode.
    static func image(forCoverArtId coverArtId: String) -> UIImage? {
        guard let url = SharedStorage.coverArtCacheDirectory?.appendingPathComponent("\(coverArtId).jpg") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Decodes a packed RGB Int (0xRRGGBB) to a SwiftUI Color.
    static func color(fromPacked packed: Int) -> Color {
        let r = Double((packed >> 16) & 0xFF) / 255.0
        let g = Double((packed >> 8) & 0xFF) / 255.0
        let b = Double(packed & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Reads the latest recently played track from SharedStorage, or nil if empty.
    static func latestRecentlyPlayed() -> SharedTrackInfo? {
        guard let data = SharedStorage.defaults.data(forKey: SharedStorageKey.recentlyPlayedItems.rawValue),
              let items = try? JSONDecoder().decode([SharedTrackInfo].self, from: data) else {
            return nil
        }
        return items.first
    }

    /// Dominant color for a coverArtId, falling back to CassetteAccent if absent.
    static func dominantColor(forCoverArtId coverArtId: String?) -> Color {
        let fallback = Color("CassetteAccent")
        guard let coverArtId,
              let dict = SharedStorage.defaults.dictionary(forKey: SharedStorageKey.dominantColors.rawValue),
              let packed = dict[coverArtId] as? Int else {
            return fallback
        }
        return color(fromPacked: packed)
    }
}
#endif
