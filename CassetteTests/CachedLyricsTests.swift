// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

@Suite("CachedLyrics")
struct CachedLyricsTests {

    @Test func insertAndFetchByCompositeKey() throws {
        let container = try ModelContainer(
            for: Schema([CachedLyrics.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let serverId = UUID()
        let songId = "song-abc"

        context.insert(CachedLyrics(songId: songId, serverId: serverId, jsonPayload: Data("{}".utf8)))
        try context.save()

        let key = "\(serverId.uuidString):\(songId)"
        let results = try context.fetch(
            FetchDescriptor<CachedLyrics>(predicate: #Predicate { $0.compositeKey == key })
        )
        #expect(results.count == 1)
        #expect(results.first?.songId == songId)
        #expect(results.first?.serverId == serverId)
    }

    @Test func lyricsListRoundTrip() throws {
        let original = LyricsList(structuredLyrics: [
            StructuredLyrics(
                lang: "en",
                synced: true,
                line: [
                    Line(value: "Hello world", start: 1000),
                    Line(value: "Goodbye", start: 5000)
                ],
                displayArtist: "Test Artist",
                displayTitle: "Test Song",
                offset: 100
            ),
            StructuredLyrics(lang: "fr", synced: false, line: [Line(value: "Bonjour")])
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LyricsList.self, from: data)
        #expect(decoded == original)
    }
}
