// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftSonic

protocol RadioServiceProtocol: AnyObject, Sendable {
    func listStations(forceRefresh: Bool) async throws -> [InternetRadioStation]
    func cachedStations() async -> [InternetRadioStation]?
    func clearCache() async
}
