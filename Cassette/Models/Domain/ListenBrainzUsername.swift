// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// What Cassette is entitled to refuse in a ListenBrainz username.
///
/// Very little. The name belongs to ListenBrainz, not to us, and the previous rule — an allowlist
/// of `[A-Za-z0-9_-]` — rejected real accounts: a dot is legal there, and so are plenty of
/// characters an allowlist written from memory never anticipates. Only ListenBrainz can say
/// whether a name exists, and it answers that with a 404.
///
/// So the check keeps what would genuinely break a request, and hands the rest to the server.
nonisolated enum ListenBrainzUsername {
    /// ListenBrainz caps names well below this; the bound exists to keep a pasted novel out of a URL.
    static let maxLength = 40

    /// A name that cannot work, whatever the server thinks of it: nothing to send, too long to be
    /// real, a space or a newline (never part of a name, and usually a bad paste), or a slash,
    /// which would silently point the request at another path.
    static func isPlausible(_ username: String) -> Bool {
        guard (1...maxLength).contains(username.count) else { return false }
        return !username.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
                || scalar == "/"
        }
    }

    /// The name as a single path segment. Percent-encoding here is what lets the rule above stay
    /// this permissive: anything legal in a name but not in a URL is escaped rather than refused.
    static func pathSegment(_ username: String) -> String? {
        username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }
}
