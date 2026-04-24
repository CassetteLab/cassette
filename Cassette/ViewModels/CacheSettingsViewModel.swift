// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

@Observable
@MainActor
final class CacheSettingsViewModel {
    var usedBytesFormatted: String = "—"
    var isClearing: Bool = false

    private let cacheService: any CacheServiceProtocol

    init(cacheService: any CacheServiceProtocol) {
        self.cacheService = cacheService
    }

    func loadUsedBytes() async {
        let bytes = await cacheService.usedBytes
        usedBytesFormatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func clearCache() async {
        isClearing = true
        await cacheService.clearAll()
        await loadUsedBytes()
        isClearing = false
    }
}
