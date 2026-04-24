import Foundation
import SwiftSonic

/// Wraps a base HTTPTransport to inject custom HTTP headers on every outbound request.
///
/// Primary use case: Cloudflare Access tokens (`CF-Access-Client-Id`,
/// `CF-Access-Client-Secret`) and other reverse-proxy authentication headers.
///
/// Security contract:
/// - Header values are never logged — treat them as credentials.
/// - Headers are validated (no \\r / \\n) before storage; this transport trusts the caller.
/// - This transport only covers SwiftSonic requests. AVPlayer and URLSessionDownloadTask
///   require separate header injection at their respective call sites.
struct CustomHeadersTransport: HTTPTransport, Sendable {
    private let base: any HTTPTransport
    private let headers: [String: String]

    init(base: any HTTPTransport = URLSessionTransport(), headers: [String: String]) {
        self.base = base
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var enriched = request
        for (key, value) in headers {
            enriched.setValue(value, forHTTPHeaderField: key)
        }
        return try await base.data(for: enriched)
    }
}
