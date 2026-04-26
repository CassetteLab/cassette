// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

import SwiftUI

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

extension Color {
    /// Perceived luminance using ITU-R BT.601 coefficients.
    /// Values > 0.6 indicate a light background that needs dark content.
    var luminance: Double {
        guard let components = cgColor?.components, components.count >= 3 else { return 0.5 }
        return 0.299 * Double(components[0]) + 0.587 * Double(components[1]) + 0.114 * Double(components[2])
    }
}

extension View {
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func navigationBarTitleDisplayModeLarge() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}
