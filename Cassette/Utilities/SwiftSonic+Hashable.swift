// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftSonic

// Hashable conformances for SwiftSonic types used as NavigationLink values.
// Equality and hashing are based on the stable server-assigned id only.

extension ArtistID3: @retroactive Hashable {
    public static func == (lhs: ArtistID3, rhs: ArtistID3) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension AlbumID3: @retroactive Hashable {
    public static func == (lhs: AlbumID3, rhs: AlbumID3) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
