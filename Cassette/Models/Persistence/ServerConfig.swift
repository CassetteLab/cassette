// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

@Model
final class ServerConfig {
    var id: UUID
    var displayName: String
    var baseURL: String
    var username: String
    var isActive: Bool
    var serverVersion: String?
    var createdAt: Date

    // password + customHeaders are stored in Keychain only.
    // Keychain key: ServerCredentials.keychainKey(for: id)

    init(
        id: UUID = UUID(),
        displayName: String,
        baseURL: String,
        username: String,
        isActive: Bool = false,
        serverVersion: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.username = username
        self.isActive = isActive
        self.serverVersion = serverVersion
        self.createdAt = createdAt
    }
}
