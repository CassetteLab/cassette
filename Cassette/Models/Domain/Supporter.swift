// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// A person credited in Settings for supporting Cassette on Ko-fi.
///
/// Only the name is decoded: `since` keeps `supporters.json` in order, and `url` is not shown
/// in the app.
nonisolated struct Supporter: Decodable, Equatable, Sendable {
    let name: String
}

/// The supporters list shipped inside the app.
///
/// `supporters.json` at the repository root is copied into the bundle at build time and read
/// from there, never fetched: crediting supporters makes no network request. New names reach
/// users with the next release.
nonisolated enum SupportersList {
    /// The bundled list, read once on first access.
    static let bundled: [Supporter] = load(from: .main)

    /// Supporters in file order — oldest first — without blank names. An unreadable or
    /// missing file yields an empty list, which hides the Settings section.
    static func load(from bundle: Bundle) -> [Supporter] {
        guard let url = bundle.url(forResource: "supporters", withExtension: "json") else {
            Logger.settings.error("supporters.json is missing from the app bundle")
            return []
        }
        do {
            return try decode(from: Data(contentsOf: url))
        } catch {
            Logger.settings.error("Could not read the bundled supporters.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func decode(from data: Data) throws -> [Supporter] {
        try JSONDecoder().decode(Document.self, from: data).supporters.compactMap { supporter in
            let name = supporter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : Supporter(name: name)
        }
    }

    private nonisolated struct Document: Decodable {
        let supporters: [Supporter]
    }
}
