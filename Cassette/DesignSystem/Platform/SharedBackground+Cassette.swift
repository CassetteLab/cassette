// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(macOS)
extension ToolbarContent {
    /// Guards `.sharedBackgroundVisibility` behind macOS 26.0 availability.
    /// Falls back to a no-op on earlier macOS versions.
    @ToolbarContentBuilder
    func cassetteSharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(visibility)
        } else {
            self
        }
    }
}
#endif
