// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

// MARK: - Errors

/// Failures worth telling the user apart. Everything else collapses into `.transport`.
nonisolated enum AudioMuseError: Error, Equatable, Sendable {
    /// HTTP 400 — usually `CLAP_ENABLED=false` on the instance. Carries the server's own message,
    /// which distinguishes "search disabled" from the rarer bad-parameter cases.
    case searchDisabled(String?)
    /// The sonic analysis has never been run, so there is no index to query (HTTP 503).
    case notAnalysed
    /// Token missing, wrong, or expired (HTTP 401/403).
    case unauthorized
    case badURL
    case transport(String)
    case decoding(String)
}

// MARK: - Wire types

/// One track from `POST /api/clap/search`.
///
/// `item_id` is the *media server's* track id, not an AudioMuse-internal one — `app_server_context`
/// guarantees an internal id is never exposed, and on a single-server install the value is passed
/// straight through. So these ids go directly into a Subsonic playlist with no second lookup.
///
/// Only the four fields the app actually uses are decoded. AudioMuse also returns `similarity`,
/// `mood_vector`, `other_features` and `top_genre`; ignoring them keeps this resilient to the
/// response growing.
nonisolated struct AudioMuseTrack: Decodable, Sendable, Equatable {
    let itemId: String
    let title: String?
    /// AudioMuse names this `author`. Note it is `artist` on the chat endpoints — the API is not
    /// consistent across routes, so do not share this type with them.
    let author: String?
    let similarity: Double?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case title, author, similarity
    }
}

private struct ClapSearchResponse: Decodable {
    let results: [AudioMuseTrack]
}

// MARK: - Client

/// Talks to an AudioMuse-AI instance over its own HTTP API — a different service from the Subsonic
/// server, on its own host and port (8000 by default), with no shared authentication.
///
/// Only the two calls the mood playlists need are implemented: warmup and text search. Deliberately
/// not `/api/alchemy` (samples with a temperature, so results wander between runs) nor `/chat`
/// (routes through an LLM, needs provider keys, and takes minutes).
actor AudioMuseClient {
    private let baseURL: URL
    private let token: String?
    private let session: URLSession

    /// Generous by iOS standards, because a cold CLAP model has to load before it can answer and
    /// the weekly job has nobody waiting on it.
    static let requestTimeout: TimeInterval = 120

    init?(urlString: String, token: String?, session: URLSession = .shared) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host != nil else { return nil }
        self.baseURL = url
        self.token = token
        self.session = session
    }

    /// Loads the CLAP model and resets its idle timer.
    ///
    /// Worth calling before a batch of searches: AudioMuse evicts the model after 10 minutes idle,
    /// so a job that runs once a week ALWAYS finds it cold. Without this the first search pays the
    /// model load on top of its own work.
    ///
    /// Failure is not fatal — search still works, just slower — so this returns a Bool instead of
    /// throwing, and callers are expected to carry on either way.
    @discardableResult
    func warmup() async -> Bool {
        do {
            _ = try await send(path: "/api/clap/warmup", body: nil)
            return true
        } catch {
            Logger.moodPlaylists.warning("[AUDIOMUSE] warmup failed, searching cold: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Free-text sonic search: returns tracks whose *sound* matches the prompt.
    ///
    /// - Parameters:
    ///   - query: English free text ("energetic upbeat high energy"). CLAP embeds audio against
    ///     English, so this is not a string to localise.
    ///   - limit: clamped server-side to 1...500.
    func search(query: String, limit: Int) async throws -> [AudioMuseTrack] {
        let payload = try JSONSerialization.data(withJSONObject: ["query": query, "limit": limit])
        let data = try await send(path: "/api/clap/search", body: payload)
        do {
            return try JSONDecoder().decode(ClapSearchResponse.self, from: data).results
        } catch {
            throw AudioMuseError.decoding(String(describing: error))
        }
    }

    // MARK: - Transport

    private func send(path: String, body: Data?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw AudioMuseError.badURL }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AudioMuseError.transport(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else { throw AudioMuseError.transport("non-HTTP response") }
        switch http.statusCode {
        case 200...299:  return data
        // 400 covers several server-side conditions — CLAP switched off, an invalid server
        // selection, a malformed query. We always send a valid query, so it is nearly always the
        // first; the server's own message is carried through rather than guessed at.
        case 400:        throw AudioMuseError.searchDisabled(Self.errorMessage(in: data))
        case 401, 403:   throw AudioMuseError.unauthorized
        case 503:        throw AudioMuseError.notAnalysed
        default:         throw AudioMuseError.transport("HTTP \(http.statusCode)")
        }
    }

    /// AudioMuse reports failures as `{"error": "..."}`. Returns nil when the body is not that shape.
    private static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }
}
