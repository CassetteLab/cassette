// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

protocol KeychainServiceProtocol: AnyObject, Sendable {
    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws
    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T?
    func delete(forKey key: String) async throws
}
