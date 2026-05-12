// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

// SwiftSonic types are Decodable-only. These retroactive Encodable conformances let Cassette
// round-trip a LyricsList through JSONEncoder for SwiftData cache persistence.
// Auto-synthesis is blocked cross-module, so encode(to:) is implemented explicitly
// using the same key names as SwiftSonic's own CodingKeys.

extension Line: @retroactive Encodable {
    private enum CodingKeys: String, CodingKey { case value, start }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(start, forKey: .start)
    }
}

extension StructuredLyrics: @retroactive Encodable {
    private enum CodingKeys: String, CodingKey {
        case lang, synced, line, displayArtist, displayTitle, offset
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(lang, forKey: .lang)
        try c.encode(synced, forKey: .synced)
        try c.encode(line, forKey: .line)
        try c.encodeIfPresent(displayArtist, forKey: .displayArtist)
        try c.encodeIfPresent(displayTitle, forKey: .displayTitle)
        try c.encode(offset, forKey: .offset)
    }
}

extension LyricsList: @retroactive Encodable {
    private enum CodingKeys: String, CodingKey { case structuredLyrics }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(structuredLyrics, forKey: .structuredLyrics)
    }
}
