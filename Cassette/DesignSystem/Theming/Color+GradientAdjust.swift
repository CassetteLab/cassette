// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Cross-platform Color helpers for the playlist gradient system: resolve sRGB components (to freeze a
/// derived base color) and produce HSB-adjusted variants (to build gradient stops from one base color).
/// The `#if` is only the UIKit/AppKit bridge — no feature gate.
extension Color {
    /// sRGB components in `0...1`, or `nil` if the color can't be resolved to RGB.
    var rgbComponents: (red: Double, green: Double, blue: Double)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b))
        #elseif canImport(AppKit)
        guard let ns = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        #else
        return nil
        #endif
    }

    /// An HSB-adjusted variant — hue wraps, saturation/brightness clamp to `0...1`. Used to derive gradient
    /// stops (lighter/darker/hue-shifted) from a single base color. Returns `self` if the color can't resolve.
    func adjusted(hue dh: Double = 0, saturation ds: Double = 0, brightness db: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        #elseif canImport(AppKit)
        guard let ns = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #else
        return self
        #endif
        var hue = (Double(h) + dh).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return Color(
            hue: hue,
            saturation: min(max(Double(s) + ds, 0), 1),
            brightness: min(max(Double(b) + db, 0), 1)
        )
    }
}
