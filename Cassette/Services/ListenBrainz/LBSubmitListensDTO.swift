// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// Track metadata extracted from a DisplayableSong for a ListenBrainz submission.
nonisolated struct LBTrackMetadata: Sendable {
    let trackName: String
    let artistName: String
    let releaseName: String?

    init(from song: DisplayableSong) {
        trackName = song.title
        artistName = song.artist ?? ""
        releaseName = song.albumName
    }
}

// MARK: - Internal Encodable request bodies (module-internal; used by ListenBrainzClient)

nonisolated struct LBSubmitListensBody: Encodable {
    enum CodingKeys: String, CodingKey {
        case listenType = "listen_type"
        case payload
    }
    let listenType: String
    let payload: [LBListenPayload]
}

nonisolated struct LBListenPayload: Encodable {
    enum CodingKeys: String, CodingKey {
        case listenedAt = "listened_at"
        case trackMetadata = "track_metadata"
    }
    let listenedAt: Int?
    let trackMetadata: LBEncodableTrackMetadata

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let ts = listenedAt { try container.encode(ts, forKey: .listenedAt) }
        try container.encode(trackMetadata, forKey: .trackMetadata)
    }
}

nonisolated struct LBEncodableTrackMetadata: Encodable {
    enum CodingKeys: String, CodingKey {
        case trackName = "track_name"
        case artistName = "artist_name"
        case releaseName = "release_name"
    }
    let trackName: String
    let artistName: String
    let releaseName: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackName, forKey: .trackName)
        try container.encode(artistName, forKey: .artistName)
        if let rn = releaseName { try container.encode(rn, forKey: .releaseName) }
    }
}
