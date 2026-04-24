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
