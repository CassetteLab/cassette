// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
    /// Base URL of the AudioMuse-AI instance that analysed THIS server's library, e.g.
    /// `http://nas.local:8000`. Per-server rather than global because the ids AudioMuse returns
    /// are this media server's track ids — pointing it at another server would yield ids that
    /// resolve to nothing. `nil` when the user has not set one up.
    ///
    /// The API token lives in Keychain beside the password, in `ServerCredentials`.
    var audioMuseURL: String?

    // password + customHeaders are stored in Keychain only.
    // Keychain key: ServerCredentials.keychainKey(for: id)

    init(
        id: UUID = UUID(),
        displayName: String,
        baseURL: String,
        username: String,
        isActive: Bool = false,
        serverVersion: String? = nil,
        createdAt: Date = Date(),
        audioMuseURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.username = username
        self.isActive = isActive
        self.serverVersion = serverVersion
        self.createdAt = createdAt
        self.audioMuseURL = audioMuseURL
    }
}
