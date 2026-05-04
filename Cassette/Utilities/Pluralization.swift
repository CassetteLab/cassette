// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

extension Int {
    func plural(_ singular: String, _ plural: String) -> String {
        "\(self) \(self == 1 ? singular : plural)"
    }
}
