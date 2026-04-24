// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum MediaSource: Sendable {
    case downloaded(URL)
    case cached(URL)
    /// Remote stream. Custom headers must be injected into every request to reach
    /// Cloudflare-protected (or other reverse-proxy) hosts.
    case stream(URL, customHeaders: [String: String])

    var url: URL {
        switch self {
        case .downloaded(let url), .cached(let url), .stream(let url, _):
            return url
        }
    }

    var customHeaders: [String: String] {
        if case .stream(_, let headers) = self { return headers }
        return [:]
    }
}
