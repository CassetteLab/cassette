// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

private let _contrastLogger = Logger(subsystem: "fr.mathieu-dubart.Cassette", category: "ColorContrast")

extension CassetteColors {
    // Light (#9F86FA): WCAG relative luminance ≈ 0.314
    // Dark  (#4C28D4): WCAG relative luminance ≈ 0.078
    private static let accentFgLight = Color(hex: "#9F86FA")
    private static let accentFgDark  = Color(hex: "#4C28D4")
    private static let luminanceFgLight: Double = 0.314
    private static let luminanceFgDark:  Double = 0.078
    static var contrastThreshold: Double = 1.7

    /// Returns whichever accentForeground variant achieves WCAG 2.1 contrast (≥3.0:1)
    /// against `background`. When both or neither pass, prefers higher contrast.
    /// Falls back to `accentFgDark` when sRGB extraction is unavailable.
    static func accentForeground(on background: Color) -> Color {
        guard let lBg = sRGBLuminance(of: background) else {
            // TODO: remove debug logging
            _contrastLogger.debug("[Contrast] extraction failed → fallback accentFgDark")
            return accentFgDark
        }
        let cLight = contrastRatio(lBg, luminanceFgLight)
        let cDark  = contrastRatio(lBg, luminanceFgDark)
        let lightPasses = cLight >= contrastThreshold
        let darkPasses  = cDark  >= contrastThreshold

        // TODO: remove debug logging
        if let (r, g, b) = sRGBComponents(of: background) {
            _contrastLogger.debug(
                "[Contrast] r=\(String(format: "%.4f", r), privacy: .public) g=\(String(format: "%.4f", g), privacy: .public) b=\(String(format: "%.4f", b), privacy: .public) | lBg=\(String(format: "%.4f", lBg), privacy: .public) cLight=\(String(format: "%.3f", cLight), privacy: .public) cDark=\(String(format: "%.3f", cDark), privacy: .public) | lightPasses=\(lightPasses, privacy: .public) darkPasses=\(darkPasses, privacy: .public) threshold=\(contrastThreshold, privacy: .public)"
            )
        }

        if lightPasses != darkPasses {
            let chosen = lightPasses ? "accentFgLight" : "accentFgDark"
            // TODO: remove debug logging
            _contrastLogger.debug("[Contrast] branch=threshold-split → \(chosen, privacy: .public)")
            return lightPasses ? accentFgLight : accentFgDark
        }
        // Both pass or both fail: pick whichever has higher contrast.
        let chosen = lBg > 0.179 ? "accentFgDark" : "accentFgLight"
        // TODO: remove debug logging
        _contrastLogger.debug("[Contrast] branch=luminance-fallback lBg>\(0.179) → \(chosen, privacy: .public)")
        return lBg > 0.179 ? accentFgDark : accentFgLight
    }

    // MARK: - WCAG dead-zone background adjustment

    // WCAG dead-zone background adjustment
    /// Returns a lightened version of `color` (blended toward white in sRGB)
    /// such that the dark accent variant achieves at least `contrastThreshold`.
    /// If the original color already gives sufficient contrast, returns it unchanged.
    /// If white itself can't achieve the target (shouldn't happen), returns .white.
    static func adjustedBackground(_ color: Color, contrastThreshold: Double = Self.contrastThreshold) -> Color {
        let components: (Double, Double, Double, Double)?
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        components = ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            ? (Double(r), Double(g), Double(b), Double(a)) : nil
        #elseif canImport(AppKit)
        if let ns = NSColor(color).usingColorSpace(.deviceRGB) {
            components = (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
        } else {
            components = nil
        }
        #else
        components = nil
        #endif

        guard let (dr, dg, db, da) = components else { return color }

        let lBg = 0.2126 * linearize(dr) + 0.7152 * linearize(dg) + 0.0722 * linearize(db)
        let lBgTarget = contrastThreshold * (luminanceFgDark + 0.05) - 0.05
        guard lBgTarget > lBg else { return color }

        // Binary search for minimum blend-toward-white factor t ∈ [0, 1]
        var lo = 0.0, hi = 1.0
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            let rB = dr + mid * (1 - dr)
            let gB = dg + mid * (1 - dg)
            let bB = db + mid * (1 - db)
            let lB = 0.2126 * linearize(rB) + 0.7152 * linearize(gB) + 0.0722 * linearize(bB)
            if lB >= lBgTarget { hi = mid } else { lo = mid }
        }

        let t = hi
        return Color(
            red:     dr + t * (1 - dr),
            green:   dg + t * (1 - dg),
            blue:    db + t * (1 - db),
            opacity: da
        )
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
