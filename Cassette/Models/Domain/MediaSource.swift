// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum MediaSource: Sendable {
    case downloaded(URL)
    case cached(URL)
    /// Remote stream of a finite-duration song. Custom headers must be injected
    /// into every request to reach Cloudflare-protected (or other reverse-proxy) hosts.
    case stream(URL, customHeaders: [String: String])
    /// Live audio stream (Internet Radio Station). Infinite-duration, not scrubbable,
    /// not cacheable. Custom headers may be required when the radio host is reached
    /// via the user's Navidrome reverse proxy.
    case liveStream(URL, customHeaders: [String: String], stationId: String)

    var url: URL {
        switch self {
        case .downloaded(let url), .cached(let url):
            return url
        case .stream(let url, _), .liveStream(let url, _, _):
            return url
        }
    }

    var customHeaders: [String: String] {
        switch self {
        case .downloaded, .cached:
            return [:]
        case .stream(_, let headers), .liveStream(_, let headers, _):
            return headers
        }
    }

    /// Whether this source represents a live stream (radio) — non-scrubbable, infinite duration.
    var isLiveStream: Bool {
        if case .liveStream = self { return true }
        return false
    }
}
