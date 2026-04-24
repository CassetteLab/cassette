// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if (macOS)
import AppKit
#endif
import Foundation
import MediaPlayer
import OSLog

/// Loads and caches artwork images for MPNowPlayingInfoCenter.
/// Isolated actor so concurrent artwork fetches don't race on the cache dictionary.
actor ArtworkLoader {
    private var cache: [URL: MPMediaItemArtwork] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    /// Returns cached artwork if available, otherwise fetches from `url` injecting
    /// `headers` into the request (required for Cloudflare-protected hosts).
    func artwork(for url: URL, headers: [String: String]) async -> MPMediaItemArtwork? {
        if let cached = cache[url] { return cached }

        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        guard let (data, _) = try? await session.data(for: request),
              let image = PlatformImage(data: data) else {
            Logger.player.warning("ArtworkLoader: failed to fetch artwork from \(url, privacy: .public)")
            return nil
        }

        let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in image }
        cache[url] = artwork
        return artwork
    }

    func clearCache() {
        cache.removeAll()
    }
}
