// Cassette
// Copyright (C) 2026 Mathieu Dubart
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cross-platform clipboard abstraction.
/// Mirrors the PlatformImage pattern: one call site, two platform implementations.
nonisolated enum PlatformPasteboard {
    /// Copies `string` to the system clipboard.
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
