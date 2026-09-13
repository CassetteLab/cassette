// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Testing
@testable import Cassette

@Suite("SupportersList")
struct SupportersListTests {

    @Test("decodes names in file order, ignoring the readme, since, url and tier")
    func decodesNamesInFileOrder() throws {
        let json = """
        {
          "_readme": ["Rules for maintainers."],
          "supporters": [
            { "name": "Early", "since": "2026-08", "tier": "sticker" },
            { "name": "Later", "since": "2026-09", "url": "https://example.com" }
          ]
        }
        """
        let supporters = try SupportersList.decode(from: Data(json.utf8))
        #expect(supporters == [Supporter(name: "Early"), Supporter(name: "Later")])
    }

    @Test("an empty list decodes to no supporters")
    func emptyList() throws {
        let supporters = try SupportersList.decode(from: Data(#"{ "supporters": [] }"#.utf8))
        #expect(supporters.isEmpty)
    }

    @Test("names are trimmed and blank names are dropped")
    func trimsAndDropsBlankNames() throws {
        let json = """
        { "supporters": [
          { "name": "  Sam  ", "since": "2026-09" },
          { "name": " ", "since": "2026-09" }
        ] }
        """
        let supporters = try SupportersList.decode(from: Data(json.utf8))
        #expect(supporters == [Supporter(name: "Sam")])
    }

    @Test("a document without a supporters array throws")
    func missingSupportersThrows() {
        #expect(throws: DecodingError.self) {
            try SupportersList.decode(from: Data(#"{ "names": [] }"#.utf8))
        }
    }

    @Test("the app bundle ships a readable supporters.json")
    func bundledFileDecodes() throws {
        let url = try #require(Bundle.main.url(forResource: "supporters", withExtension: "json"))
        _ = try SupportersList.decode(from: Data(contentsOf: url))
    }
}
