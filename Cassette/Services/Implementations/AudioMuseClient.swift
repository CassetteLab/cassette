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
    /// The instance answered with its INTERNAL canonical ids (`fp_...`) instead of the media
    /// server's own. They mean nothing to Subsonic, which silently drops them and stores an empty
    /// playlist, so this is caught here rather than allowed downstream.
    ///
    /// Cause, from AudioMuse's own registry: the `track_server_map` table has no row linking those
    /// canonical ids to the server's track ids, which it logs as "unswept default?". Only a sweep
    /// on the AudioMuse side fixes it — nothing here can translate the ids.
    case internalIdsOnly
    case transport(String)
    case decoding(String)
}

// MARK: - Wire types

/// One track from `POST /api/clap/search`.
///
/// `item_id` is MEANT to be the media server's track id — AudioMuse's own source says an internal
/// canonical (`fp_`) id must never be exposed. In practice it can be, when its catalogue holds no
/// mapping for the id: an instance answered a real query with `fp_2057…` for every result. Those go
/// into a Subsonic playlist, get silently dropped, and leave it empty. `search` therefore refuses
/// them rather than trusting the contract.
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
    let album: String?
    let similarity: Double?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case title, author, album, similarity
    }

    /// True when the id is AudioMuse's internal one, which the music server cannot match.
    var hasInternalId: Bool { itemId.hasPrefix(AudioMuseClient.internalIdPrefix) }

    /// Metadata view used to find this track in the library when its id is unusable.
    var descriptor: TrackDescriptor? {
        guard let title, !title.isEmpty else { return nil }
        return TrackDescriptor(title: title, artist: author, album: album)
    }
}

private nonisolated struct ClapSearchResponse: Decodable {
    let results: [AudioMuseTrack]
}

private nonisolated struct ServersResponse: Decodable {
    nonisolated struct Server: Decodable {
        let serverId: String?
        let name: String?
        enum CodingKeys: String, CodingKey { case serverId = "server_id", name }
    }
    let servers: [Server]
    let defaultId: String?
    enum CodingKeys: String, CodingKey { case servers, defaultId = "default_id" }
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
    /// Media server to scope results to, resolved once from `/api/servers`.
    ///
    /// Without it AudioMuse falls back to its default server, and on a catalogue where the id
    /// mapping is incomplete that path hands back canonical `fp_` ids — useless to Subsonic.
    /// Naming the server explicitly is what makes it translate to that server's own ids.
    private var selectedServer: String??

    /// Ids AudioMuse marks as internal. Documented in its own source: "An API response must NEVER
    /// expose the internal canonical (fp_) id".
    static let internalIdPrefix = "fp_" 

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
        await resolveServerIfNeeded()
        do {
            _ = try await send(path: "/api/clap/warmup", body: nil)
            return true
        } catch {
            Logger.moodPlaylists.warning("[AUDIOMUSE] warmup failed, searching cold: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Reads `/api/servers` and keeps the default server's id, so searches can be scoped to it.
    /// Failure is not fatal — the search still runs unscoped and the fp_ guard catches the fallout.
    private func resolveServerIfNeeded() async {
        guard selectedServer == nil else { return }
        do {
            let data = try await send(path: "/api/servers", body: nil, method: "GET")
            let decoded = try JSONDecoder().decode(ServersResponse.self, from: data)
            let resolved = decoded.defaultId ?? decoded.servers.first?.serverId ?? decoded.servers.first?.name
            selectedServer = .some(resolved)
            Logger.moodPlaylists.info("[AUDIOMUSE] \(decoded.servers.count, privacy: .public) server(s) configured, scoping to '\(resolved ?? "default", privacy: .public)'")
        } catch {
            selectedServer = .some(nil)
            Logger.moodPlaylists.warning("[AUDIOMUSE] could not list servers, searching unscoped: \(String(describing: error), privacy: .public)")
        }
    }

    /// Free-text sonic search: returns tracks whose *sound* matches the prompt.
    ///
    /// - Parameters:
    ///   - query: English free text ("energetic upbeat high energy"). CLAP embeds audio against
    ///     English, so this is not a string to localise.
    ///   - limit: clamped server-side to 1...500.
    func search(query: String, limit: Int) async throws -> [AudioMuseTrack] {
        await resolveServerIfNeeded()
        var body: [String: Any] = ["query": query, "limit": limit]
        if let server = selectedServer ?? nil { body["server"] = server }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(path: "/api/clap/search", body: payload)

        let results: [AudioMuseTrack]
        do {
            results = try JSONDecoder().decode(ClapSearchResponse.self, from: data).results
        } catch {
            throw AudioMuseError.decoding(String(describing: error))
        }

        // Internal ids are NOT filtered here. They come with title and artist, which is enough to
        // find the track in the library — throwing them away would discard a recoverable result.
        // The provider decides what to do with them.
        return results
    }

    // MARK: - Transport

    private func send(path: String, body: Data?, method: String = "POST") async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw AudioMuseError.badURL }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = method
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
