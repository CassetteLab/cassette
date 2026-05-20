// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
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
///
/// Timeout policy: the default initializer creates a dedicated URLSession with
/// `timeoutIntervalForRequest = 30` and `timeoutIntervalForResource = 30`.
/// The resource timeout (default 7 days in URLSession) is the critical guard
/// against hung Subsonic responses when the server triggers slow external lookups.
struct CustomHeadersTransport: HTTPTransport, Sendable {
    private let base: any HTTPTransport
    private let headers: [String: String]

    /// Normal use case. Creates a dedicated URLSession with 30-second timeouts.
    init(headers: [String: String]) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        // Session-level injection ensures headers reach Cloudflare Access on every
        // request path, including any internal URLSession hop before SwiftSonic
        // intercepts the redirect.
        config.httpAdditionalHeaders = headers
        self.base = URLSessionTransport(configuration: config)
        self.headers = headers
    }

    /// Testability / advanced use. Inject a pre-configured transport as the base.
    init(base: any HTTPTransport, headers: [String: String]) {
        self.base = base
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var enriched = request
        let hadAuthorization = enriched.value(forHTTPHeaderField: "Authorization") != nil
        let authCollision = headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame }
        for (key, value) in headers {
            enriched.setValue(value, forHTTPHeaderField: key)
        }
        let cfId = headers.first(where: { $0.key.caseInsensitiveCompare("CF-Access-Client-Id") == .orderedSame })?.value
        let cfSecret = headers.first(where: { $0.key.caseInsensitiveCompare("CF-Access-Client-Secret") == .orderedSame })?.value
        Logger.httpTransport.debug("CustomHeadersTransport: injected_keys=\(Array(headers.keys).sorted(), privacy: .private) had_auth=\(hadAuthorization, privacy: .public) auth_collision=\(authCollision, privacy: .public)")
        Logger.httpTransport.debug("CustomHeadersTransport CF headers: id=\(cfId.map { $0.isEmpty ? "EMPTY" : "SET" } ?? "ABSENT", privacy: .public) secret=\(cfSecret.map { $0.isEmpty ? "EMPTY" : "SET" } ?? "ABSENT", privacy: .public)")
        return try await base.data(for: enriched)
    }
}
