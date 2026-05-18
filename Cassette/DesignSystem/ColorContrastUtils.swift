// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension CassetteColors {
    // Light (#9F86FA): WCAG relative luminance ≈ 0.314
    // Dark  (#4C28D4): WCAG relative luminance ≈ 0.078
    private static let accentFgLight = Color(hex: "#9F86FA")
    private static let accentFgDark  = Color(hex: "#4C28D4")
    private static let luminanceFgLight: Double = 0.314
    private static let luminanceFgDark:  Double = 0.078

    /// Returns whichever accentForeground variant achieves WCAG 2.1 contrast (≥3.0:1)
    /// against `background`. When both or neither pass, prefers higher contrast.
    /// Falls back to `accentFgDark` when sRGB extraction is unavailable.
    static func accentForeground(on background: Color) -> Color {
        guard let lBg = sRGBLuminance(of: background) else { return accentFgDark }
        let cLight = contrastRatio(lBg, luminanceFgLight)
        let cDark  = contrastRatio(lBg, luminanceFgDark)
        let lightPasses = cLight >= 3.0
        let darkPasses  = cDark  >= 3.0
        if lightPasses != darkPasses { return lightPasses ? accentFgLight : accentFgDark }
        // Both pass or both fail: pick whichever has higher contrast.
        return lBg > 0.179 ? accentFgDark : accentFgLight
    }

    // MARK: - WCAG 2.1 luminance

    private static func sRGBLuminance(of color: Color) -> Double? {
        guard let (r, g, b) = sRGBComponents(of: color) else { return nil }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        let lighter = max(a, b)
        let darker  = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    // MARK: - Platform bridge

    private static func sRGBComponents(of color: Color) -> (Double, Double, Double)? {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b))
        #elseif canImport(AppKit)
        guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
        #else
        return nil
        #endif
    }
}
