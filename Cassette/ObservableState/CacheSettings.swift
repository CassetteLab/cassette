// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

/// User-configurable cache preferences persisted in UserDefaults.
/// @Observable so SettingsView updates live; stored as Double for UserDefaults compatibility
/// (all quota options ≤ 5 GB fit exactly in a 53-bit Double mantissa).
/// Injected into AppContainer; services read values via MainActor.run when needed.
@Observable
@MainActor
final class CacheSettings {
    // MARK: - Keys

    private static let ttlKey   = "cache.ttl"
    private static let quotaKey = "cache.quota"

    // MARK: - Defaults

    static let defaultTTLSeconds: Double  = 259_200        // 3 days
    static let defaultQuotaBytes: Double  = 1_073_741_824  // 1 GB

    // MARK: - Properties

    /// TTL in seconds. Special value: `.greatestFiniteMagnitude` = "until cache is full".
    var ttlSeconds: Double {
        didSet { UserDefaults.standard.set(ttlSeconds, forKey: Self.ttlKey) }
    }

    /// Quota in bytes stored as Double. Special value: `.greatestFiniteMagnitude` = "no limit".
    var quotaBytes: Double {
        didSet { UserDefaults.standard.set(quotaBytes, forKey: Self.quotaKey) }
    }

    // MARK: - Typed accessors for services

    var ttl: TimeInterval { ttlSeconds }

    var quotaInt64: Int64 {
        quotaBytes >= Double.greatestFiniteMagnitude ? Int64.max : Int64(quotaBytes)
    }

    // MARK: - Init

    init() {
        let storedTTL = UserDefaults.standard.double(forKey: Self.ttlKey)
        ttlSeconds = storedTTL > 0 ? storedTTL : Self.defaultTTLSeconds

        let storedQuota = UserDefaults.standard.double(forKey: Self.quotaKey)
        quotaBytes = storedQuota > 0 ? storedQuota : Self.defaultQuotaBytes
    }
}
