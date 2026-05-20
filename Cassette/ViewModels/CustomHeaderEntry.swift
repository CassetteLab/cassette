// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

struct CustomHeaderEntry: Identifiable {
    let id: UUID
    var key: String
    var value: String

    init(key: String = "", value: String = "") {
        self.id = UUID()
        self.key = key
        self.value = value
    }
}
