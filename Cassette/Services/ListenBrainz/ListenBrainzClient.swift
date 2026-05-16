// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// Pure HTTP actor for ListenBrainz API calls. Stateless — no caching, no persisted config.
/// Username is never logged; only HTTP status codes and rate-limit headers are logged.
actor ListenBrainzClient {
    private static let baseURL = URL(string: "https://api.listenbrainz.org/1/")!

    private let transport: any ListenBrainzTransport

    init(transport: any ListenBrainzTransport) {
        self.transport = transport
    }

    // MARK: - Username validation

    /// Returns `true` if the username exists on ListenBrainz.
    ///
    /// Uses `/1/user/{username}/listen-count` — a real JSON API endpoint that returns 200+JSON when
    /// the user exists and 404 when not. The former `/1/user/{name}` route is an HTML web route
    /// (308 redirect + HTML body) and is not suitable for API use.
    ///
    /// Local format check (`[a-zA-Z0-9_-]{1,40}`) runs before any network call.
    func validateUsername(_ username: String) async throws -> Bool {
        guard Self.isValidUsernameFormat(username) else {
            throw ListenBrainzError.invalidUsername
        }

        guard let url = URL(string: "https://api.listenbrainz.org/1/user/\(username)/listen-count") else {
            throw ListenBrainzError.invalidUsername
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as ListenBrainzError {
            throw error
        } catch {
            throw ListenBrainzError.network(error)
        }

        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            Logger.listenBrainz.debug("validateUsername X-RateLimit-Remaining: \(remaining, privacy: .public)")
        }
        Logger.listenBrainz.debug("validateUsername HTTP \(response.statusCode, privacy: .public)")

        switch response.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(LBListenCountResponse.self, from: data)
                Logger.listenBrainz.debug("validateUsername listen-count=\(decoded.payload.count, privacy: .public)")
                return true
            } catch {
                throw ListenBrainzError.decoding(error)
            }
        case 401:
            throw ListenBrainzError.unauthorized
        case 404:
            throw ListenBrainzError.userNotFound
        case 429:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw ListenBrainzError.rateLimited(retryAfter: delay)
        case 500...599:
            throw ListenBrainzError.httpError(statusCode: response.statusCode)
        default:
            throw ListenBrainzError.httpError(statusCode: response.statusCode)
        }
    }

    // MARK: - Fresh releases

    /// Returns personalized fresh releases for the given user.
    ///
    /// - Parameters:
    ///   - daysWindow: Date window (in days) relative to today.
    ///   - includePast: Include releases from the past `daysWindow` days (default `true`).
    ///   - includeFuture: Include upcoming releases within `daysWindow` days (default `false`).
    ///
    /// Username is never logged.
    func freshReleases(
        forUser username: String,
        daysWindow: Int = 90,
        includePast: Bool = true,
        includeFuture: Bool = false
    ) async throws -> [LBFreshReleaseDTO] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.listenbrainz.org"
        components.path = "/1/user/\(username)/fresh_releases"
        components.queryItems = [
            URLQueryItem(name: "days",   value: String(daysWindow)),
            URLQueryItem(name: "past",   value: includePast ? "true" : "false"),
            URLQueryItem(name: "future", value: includeFuture ? "true" : "false"),
        ]
        guard let url = components.url else {
            throw ListenBrainzError.invalidUsername
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let start = Date()
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as ListenBrainzError {
            throw error
        } catch {
            throw ListenBrainzError.network(error)
        }

        let elapsed = Date().timeIntervalSince(start)
        Logger.listenBrainz.debug("freshReleases HTTP \(response.statusCode, privacy: .public) in \(String(format: "%.2f", elapsed), privacy: .public)s")
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            Logger.listenBrainz.debug("freshReleases X-RateLimit-Remaining: \(remaining, privacy: .public)")
        }

        switch response.statusCode {
        case 200:
            break
        case 404:
            throw ListenBrainzError.userNotFound
        case 429:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw ListenBrainzError.rateLimited(retryAfter: delay)
        case 500...599:
            throw ListenBrainzError.httpError(statusCode: response.statusCode)
        default:
            throw ListenBrainzError.httpError(statusCode: response.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(LBFreshReleasesResponse.self, from: data)
            let count = decoded.payload.releases.count
            Logger.listenBrainz.debug("freshReleases parsed \(count, privacy: .public) releases")
            return decoded.payload.releases
        } catch {
            throw ListenBrainzError.decoding(error)
        }
    }

    // MARK: - Similar artists

    /// Fetches artists similar to the given MBID from the ListenBrainz artist page endpoint.
    ///
    /// Uses `POST https://listenbrainz.org/artist/{mbid}/` — an internal LB endpoint (not a
    /// versioned public REST API). Returns up to 18 artists ordered by similarity score.
    /// Returns `[]` on 404 (artist unknown to LB) rather than throwing.
    func similarArtists(mbid: String) async throws -> [LBSimilarArtistDTO] {
        guard let url = URL(string: "https://listenbrainz.org/artist/\(mbid)/") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as ListenBrainzError {
            throw error
        } catch {
            throw ListenBrainzError.network(error)
        }

        Logger.listenBrainz.debug("similarArtists HTTP \(response.statusCode, privacy: .public) for mbid=\(mbid, privacy: .public)")

        switch response.statusCode {
        case 200:
            break
        case 404:
            Logger.listenBrainz.debug("similarArtists: artist not found in LB for mbid=\(mbid, privacy: .public)")
            return []
        case 429:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw ListenBrainzError.rateLimited(retryAfter: delay)
        case 500...599:
            throw ListenBrainzError.httpError(statusCode: response.statusCode)
        default:
            throw ListenBrainzError.httpError(statusCode: response.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(LBSimilarArtistsResponse.self, from: data)
            let count = decoded.similarArtists.artists.count
            Logger.listenBrainz.debug("similarArtists: parsed \(count, privacy: .public) artists")
            return decoded.similarArtists.artists
        } catch {
            throw ListenBrainzError.decoding(error)
        }
    }

    // MARK: - Helpers

    private static func isValidUsernameFormat(_ username: String) -> Bool {
        guard (1...40).contains(username.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
