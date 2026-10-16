// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

protocol ShareServiceProtocol: AnyObject, Sendable {
    /// Creates a public link to the given songs and returns its URL.
    ///
    /// Throws ShareLinkError. No expiry is sent: the server's own default decides how long
    /// the link lives, rather than Cassette inventing a policy on the user's behalf.
    func createPublicLink(songIds: [String], description: String?) async throws -> URL
}
