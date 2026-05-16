// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

struct AlbumRecommendation: Sendable, Equatable {
    let id: String?
    let title: String
    let artistName: String
    let releaseDate: Date?
    let coverArtURL: URL?
    let inLibrary: Bool
}
