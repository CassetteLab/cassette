// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

struct LBFreshReleasesResponse: Decodable, Sendable {
    let payload: LBFreshReleasesPayload
}

struct LBFreshReleasesPayload: Decodable, Sendable {
    let releases: [LBFreshReleaseDTO]
}

/// Internal DTO for a single release from the ListenBrainz fresh_releases endpoint.
/// Date parsing is intentionally deferred to the mapping layer (ListenBrainzRecommendationProvider)
/// so a malformed release_date string on one entry does not fail the entire response.
struct LBFreshReleaseDTO: Decodable, Sendable {
    let artistCreditName: String
    let releaseName: String
    /// Raw "YYYY-MM-DD" string. `nil` when absent in the response.
    let releaseDate: String?
    let releaseGroupMbid: String?
    /// Cover Art Archive image ID (64-bit; can exceed Int32 range).
    let caaId: Int64?
    /// The release MBID that hosts the CAA image referenced by `caaId`.
    let caaReleaseMbid: String?

    enum CodingKeys: String, CodingKey {
        case artistCreditName = "artist_credit_name"
        case releaseName      = "release_name"
        case releaseDate      = "release_date"
        case releaseGroupMbid = "release_group_mbid"
        case caaId            = "caa_id"
        case caaReleaseMbid   = "caa_release_mbid"
    }
}
