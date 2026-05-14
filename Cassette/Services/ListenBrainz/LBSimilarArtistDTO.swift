// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Top-level DTO for `POST https://listenbrainz.org/artist/{mbid}/`.
/// This is a fat page endpoint; only `similarArtists` is consumed.
nonisolated struct LBSimilarArtistsResponse: Decodable, Sendable {
    let similarArtists: LBSimilarArtistsPayload
}

nonisolated struct LBSimilarArtistsPayload: Decodable, Sendable {
    let artists: [LBSimilarArtistDTO]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let failable = try container.decode([LBFailableArtistDTO].self, forKey: .artists)
        artists = failable.compactMap { $0.value }
    }

    private enum CodingKeys: String, CodingKey { case artists }
}

/// Tolerant wrapper: silently drops entries that fail to decode (e.g. missing required fields).
private nonisolated struct LBFailableArtistDTO: Decodable, Sendable {
    let value: LBSimilarArtistDTO?
    nonisolated init(from decoder: any Decoder) throws {
        value = try? LBSimilarArtistDTO(from: decoder)
    }
}

nonisolated struct LBSimilarArtistDTO: Decodable, Sendable {
    let artistMbid: String
    let name: String
    let comment: String?
    let score: Int?

    enum CodingKeys: String, CodingKey {
        case artistMbid = "artist_mbid"
        case name
        case comment
        case score
    }
}
