// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Transport abstraction for ListenBrainz HTTP calls.
///
/// Separate from SwiftSonic's HTTPTransport — ListenBrainz uses native URLSession
/// without any Subsonic-specific wrapping.
protocol ListenBrainzTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default implementation backed by a dedicated URLSession with 30-second timeouts.
/// Uses a private session rather than `.shared` so timeout configuration is isolated
/// from other in-process networking.
nonisolated struct URLSessionListenBrainzTransport: ListenBrainzTransport {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
