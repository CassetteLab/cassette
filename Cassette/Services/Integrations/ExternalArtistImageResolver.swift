// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

// MARK: - HTTP client protocol (testable)

protocol ArtistImageHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ArtistImageHTTPClient {}

// MARK: - Actor

/// Resolves out-of-library artist photos via MusicBrainz → Wikidata → Wikimedia Commons.
/// Supports both MBID-based lookup (LB-sourced recommendations) and name-based search
/// (Subsonic provider, which does not supply MBIDs).
/// Results are cached in-memory; concurrent requests for the same artist share a single Task.
actor ExternalArtistImageResolver {
    private let httpClient: any ArtistImageHTTPClient
    /// Keys: "mbid:<mbid>" or "name:<normalized-name>"
    private var cache: [String: URL?] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private var lastMBRequest: Date = .distantPast

    init(httpClient: any ArtistImageHTTPClient = URLSession.shared) {
        self.httpClient = httpClient
    }

    // MARK: - Public API

    /// Unified entry point: uses the MBID when available, otherwise searches MB by name.
    func resolveImageURL(for recommendation: SimilarArtistRecommendation) async -> URL? {
        if let mbid = recommendation.mbid?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mbid.isEmpty {
            return await resolveImageURL(forArtistMBID: mbid)
        }
        return await resolveImageURL(forArtistName: recommendation.name)
    }

    /// Resolves via a known MusicBrainz ID → Wikidata → Wikimedia Commons.
    func resolveImageURL(forArtistMBID mbid: String) async -> URL? {
        let trimmed = mbid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.artistArtwork.debug("Skipped resolution: empty MBID")
            return nil
        }
        return await resolve(key: "mbid:\(trimmed)") { await self.pipeline(mbid: trimmed) }
    }

    /// Searches MusicBrainz for the artist by name, then runs the MB→Wikidata→Commons pipeline.
    func resolveImageURL(forArtistName name: String) async -> URL? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        return await resolve(key: "name:\(normalized)") {
            guard let mbid = await self.searchMBID(forName: name) else { return nil }
            return await self.pipeline(mbid: mbid)
        }
    }

    // MARK: - Cache / dedup helper

    private func resolve(key: String, work: @escaping @Sendable () async -> URL?) async -> URL? {
        if let cached = cache[key] { return cached }
        if let existing = inflight[key] { return await existing.value }

        let task = Task<URL?, Never> { await work() }
        inflight[key] = task
        let result = await task.value
        inflight.removeValue(forKey: key)
        cache[key] = result
        return result
    }

    // MARK: - Pipeline stages

    private func pipeline(mbid: String) async -> URL? {
        guard let wikidataID = await fetchWikidataID(mbid: mbid) else { return nil }
        guard let filename = await fetchCommonsFilename(wikidataID: wikidataID) else { return nil }
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=500")
    }

    private func searchMBID(forName name: String) async -> String? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)

        await enforceMBRateLimit()

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/artist")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "artist:\"\(name)\""),
            URLQueryItem(name: "limit", value: "3"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Cassette/1.0 (mathieu.dubart@icloud.com)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        do {
            let (data, _) = try await httpClient.data(for: req)
            let decoded = try JSONDecoder().decode(MBsearchResponse.self, from: data)
            let artists = decoded.artists ?? []

            let match = artists.first { candidate in
                let score = candidate.score ?? 0
                if score >= 90 { return true }
                if score >= 80 {
                    let candidateNorm = candidate.name.lowercased().trimmingCharacters(in: .whitespaces)
                        .folding(options: .diacriticInsensitive, locale: .current)
                    return candidateNorm == normalized
                }
                return false
            }

            if let match {
                Logger.artistArtwork.debug("MB search resolved '\(name, privacy: .public)' → MBID=\(match.id, privacy: .public) score=\(match.score ?? 0, privacy: .public)")
                return match.id
            }
            Logger.artistArtwork.debug("MB search no match for '\(name, privacy: .public)' (best score=\(artists.first?.score ?? 0, privacy: .public))")
            return nil
        } catch {
            Logger.artistArtwork.warning("MB search failed for '\(name, privacy: .public)': \(error, privacy: .public)")
            return nil
        }
    }

    private func fetchWikidataID(mbid: String) async -> String? {
        await enforceMBRateLimit()

        var req = URLRequest(url: URL(string: "https://musicbrainz.org/ws/2/artist/\(mbid)?inc=url-rels&fmt=json")!)
        req.setValue("Cassette/1.0 (mathieu.dubart@icloud.com)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        do {
            let (data, _) = try await httpClient.data(for: req)
            let decoded = try JSONDecoder().decode(MBartistResponse.self, from: data)
            let wikidataRel = decoded.relations?.first {
                $0.type == "wikidata" && $0.url?.resource.contains("wikidata.org/wiki/Q") == true
            }
            guard let resource = wikidataRel?.url?.resource,
                  let qid = resource.components(separatedBy: "/").last,
                  qid.hasPrefix("Q") else {
                Logger.artistArtwork.debug("No Wikidata relation for MBID=\(mbid, privacy: .public)")
                return nil
            }
            Logger.artistArtwork.debug("MBID=\(mbid, privacy: .public) → Wikidata=\(qid, privacy: .public)")
            return qid
        } catch {
            Logger.artistArtwork.warning("MB fetch failed for MBID=\(mbid, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func fetchCommonsFilename(wikidataID: String) async -> String? {
        let urlString = "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=\(wikidataID)&props=claims&format=json"
        let req = URLRequest(url: URL(string: urlString)!, timeoutInterval: 10)

        do {
            let (data, _) = try await httpClient.data(for: req)
            let decoded = try JSONDecoder().decode(WDentitiesResponse.self, from: data)
            guard let claims = decoded.entities[wikidataID]?.claims,
                  let p18 = claims["P18"]?.first?.mainsnak.datavalue?.value else {
                Logger.artistArtwork.debug("No P18 for Wikidata=\(wikidataID, privacy: .public)")
                return nil
            }
            Logger.artistArtwork.debug("Wikidata=\(wikidataID, privacy: .public) P18=\(p18, privacy: .public)")
            return p18
        } catch {
            Logger.artistArtwork.warning("Wikidata fetch failed for \(wikidataID, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func enforceMBRateLimit() async {
        let elapsed = Date().timeIntervalSince(lastMBRequest)
        if elapsed < 1.0 {
            try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
        }
        lastMBRequest = Date()
    }
}

// MARK: - MusicBrainz response models

nonisolated private struct MBsearchResponse: Decodable {
    let artists: [MBartistCandidate]?
}

nonisolated private struct MBartistCandidate: Decodable {
    let id: String
    let name: String
    let score: Int?
}

nonisolated private struct MBartistResponse: Decodable {
    let relations: [MBrelation]?
}

nonisolated private struct MBrelation: Decodable {
    let type: String
    let url: MBurl?
}

nonisolated private struct MBurl: Decodable {
    let resource: String
}

// MARK: - Wikidata response models

nonisolated private struct WDentitiesResponse: Decodable {
    let entities: [String: WDentity]
}

nonisolated private struct WDentity: Decodable {
    let claims: [String: [WDclaim]]?
}

nonisolated private struct WDclaim: Decodable {
    let mainsnak: WDmainsnak
}

nonisolated private struct WDmainsnak: Decodable {
    let datavalue: WDdatavalue?
}

nonisolated private struct WDdatavalue: Decodable {
    /// P18 values are plain strings (Commons filenames). Other property types use nested
    /// objects — we decode only the string case and return nil for everything else.
    let value: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try? container.decode(String.self, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey { case value }
}
