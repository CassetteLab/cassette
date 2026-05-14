// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

actor ListenBrainzRecommendationProvider: RecommendationProvider {
    private let client: ListenBrainzClient
    private let service: ListenBrainzService
    private let libraryService: any LibraryServiceProtocol
    private let cacheTTL: TimeInterval

    private struct CacheKey: Hashable {
        let username: String
        let daysWindow: Int
    }

    private struct CacheEntry {
        let data: [AlbumRecommendation]
        let expiresAt: Date
    }

    private var cache: [CacheKey: CacheEntry] = [:]

    // force-unwrap safe: compile-time string constant
    nonisolated private static let coverArtArchiveBase = URL(string: "https://coverartarchive.org")!

    nonisolated private static let releaseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    init(
        client: ListenBrainzClient,
        service: ListenBrainzService,
        libraryService: any LibraryServiceProtocol,
        cacheTTL: TimeInterval = 6 * 3600
    ) {
        self.client = client
        self.service = service
        self.libraryService = libraryService
        self.cacheTTL = cacheTTL
    }

    // MARK: - RecommendationProvider

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        let snapshot = await service.currentSnapshot()
        guard snapshot.isEnabled, let username = snapshot.username else { return [] }

        let key = CacheKey(username: username, daysWindow: daysWindow)
        if let entry = cache[key], Date() < entry.expiresAt {
            return Array(entry.data.prefix(limit))
        }

        let dtos: [LBFreshReleaseDTO]
        do {
            dtos = try await client.freshReleases(forUser: username, daysWindow: daysWindow)
        } catch ListenBrainzError.userNotFound {
            Logger.listenBrainz.warning("freshReleases: LB user not found — returning empty (stale username?)")
            return []
        }

        let mapped = dtos.map { map($0) }
        let sorted = mapped.sorted { a, b in
            switch (a.releaseDate, b.releaseDate) {
            case let (lhs?, rhs?): return lhs > rhs
            case (_?, nil):        return true
            case (nil, _?):        return false
            case (nil, nil):       return false
            }
        }
        cache[key] = CacheEntry(data: sorted, expiresAt: Date().addingTimeInterval(cacheTTL))
        let ttl = Int(cacheTTL)
        Logger.listenBrainz.debug("freshReleases: cached \(sorted.count, privacy: .public) releases for daysWindow=\(daysWindow, privacy: .public) (TTL \(ttl, privacy: .public)s)")
        return Array(sorted.prefix(limit))
    }

    func similarArtists(toArtistID artistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] {
        // Resolve Subsonic artist ID → MBID via getArtistInfo2
        let mbid: String
        do {
            guard let resolved = try await libraryService.getArtistMBID(forArtistID: artistID) else {
                Logger.listenBrainz.debug("similarArtists: no MBID for artistID=\(artistID, privacy: .public)")
                return []
            }
            mbid = resolved
        } catch {
            Logger.listenBrainz.warning("similarArtists: MBID lookup failed for artistID=\(artistID, privacy: .public)")
            return []
        }

        // Fetch from LB (up to 18, pre-sorted by score desc)
        let dtos: [LBSimilarArtistDTO]
        do {
            dtos = try await client.similarArtists(mbid: mbid)
        } catch {
            Logger.listenBrainz.warning("similarArtists: LB fetch failed for mbid=\(mbid, privacy: .public)")
            return []
        }

        // Enrich with inLibrary flag using name-based lookup against the local artist index
        let limited = Array(dtos.prefix(limit))
        var results: [SimilarArtistRecommendation] = []
        results.reserveCapacity(limited.count)

        for dto in limited {
            if let libraryArtist = await libraryService.findArtist(byName: dto.name) {
                results.append(SimilarArtistRecommendation(
                    id: libraryArtist.id,
                    name: dto.name,
                    coverArt: libraryArtist.coverArt,
                    inLibrary: true,
                    mbid: dto.artistMbid
                ))
            } else {
                results.append(SimilarArtistRecommendation(
                    id: dto.artistMbid,
                    name: dto.name,
                    coverArt: nil,
                    inLibrary: false,
                    mbid: dto.artistMbid
                ))
            }
        }

        let inLibraryCount = results.filter { $0.inLibrary }.count
        Logger.listenBrainz.debug("similarArtists: \(results.count, privacy: .public) results (\(inLibraryCount, privacy: .public) in library) for mbid=\(mbid, privacy: .public)")
        return results
    }

    // MARK: - Mapping

    private func map(_ dto: LBFreshReleaseDTO) -> AlbumRecommendation {
        let releaseDate: Date?
        if let dateStr = dto.releaseDate {
            releaseDate = Self.releaseDateFormatter.date(from: dateStr)
            if releaseDate == nil {
                Logger.listenBrainz.warning("freshReleases: unparseable release_date '\(dateStr, privacy: .public)'")
            }
        } else {
            releaseDate = nil
        }

        let coverArtURL: URL?
        if let caaId = dto.caaId, let caaReleaseMbid = dto.caaReleaseMbid {
            coverArtURL = Self.coverArtArchiveBase
                .appendingPathComponent("release")
                .appendingPathComponent(caaReleaseMbid)
                .appendingPathComponent("\(caaId)-250.jpg")
        } else if let rgMbid = dto.releaseGroupMbid {
            coverArtURL = Self.coverArtArchiveBase
                .appendingPathComponent("release-group")
                .appendingPathComponent(rgMbid)
                .appendingPathComponent("front-250")
        } else {
            coverArtURL = nil
        }

        return AlbumRecommendation(
            id: dto.releaseGroupMbid,
            title: dto.releaseName,
            artistName: dto.artistCreditName,
            releaseDate: releaseDate,
            coverArtURL: coverArtURL,
            inLibrary: false
        )
    }
}
