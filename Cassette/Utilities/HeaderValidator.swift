// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Validates HTTP header names and values against RFC 7230 rules.
nonisolated enum HeaderValidator {

    /// Returns true if every character in `name` is an RFC 7230 tchar.
    ///
    /// tchar = ALPHA / DIGIT / "!" / "#" / "$" / "%" / "&" / "'" /
    ///         "*" / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy(isTChar)
    }

    /// Returns true if `value` contains no CR, LF, or NUL characters.
    static func isValidValue(_ value: String) -> Bool {
        !value.contains("\r") && !value.contains("\n") && !value.contains("\0")
    }

    private static func isTChar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 0x41 && v <= 0x5A) || // A-Z
               (v >= 0x61 && v <= 0x7A) || // a-z
               (v >= 0x30 && v <= 0x39) || // 0-9
               v == 0x21 ||                // !
               v == 0x23 ||                // #
               v == 0x24 ||                // $
               v == 0x25 ||                // %
               v == 0x26 ||                // &
               v == 0x27 ||                // '
               v == 0x2A ||                // *
               v == 0x2B ||                // +
               v == 0x2D ||                // -
               v == 0x2E ||                // .
               v == 0x5E ||                // ^
               v == 0x5F ||                // _
               v == 0x60 ||                // `
               v == 0x7C ||                // |
               v == 0x7E                   // ~
    }
}
