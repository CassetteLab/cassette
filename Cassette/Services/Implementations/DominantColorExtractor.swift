// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import CoreImage
import OSLog

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Extracts the dominant (average) color from a cover art image using CIAreaAverage.
/// Results are cached in memory keyed by coverArtId and persisted to UserDefaults as packed
/// 0xRRGGBB integers so dominant colors are available immediately at cold start.
///
/// TODO(v2.0): UserDefaults is used intentionally here for two reasons:
///   1. Synchronous cold-start hydration in init() — SwiftData requires async context.
///   2. cachedColors() feeds WidgetSyncService for App Group sharing, which UserDefaults
///      handles natively across process boundaries. Migrating requires an async init
///      refactor and a separate widget-sync write path.
@MainActor
@Observable
final class DominantColorExtractor {
    // v3: back to WHOLE-IMAGE averages (the representative dominant colour) — a fresh key so the v2 bottom-strip
    // colours are dropped and every cover re-extracts with the whole-image method.
    private static let userDefaultsKey = "cassette.dominantColor.cache.v3"
    private static let legacyUserDefaultsKey = "cassette.dominantColor.cache.v2"
    /// User-picked colour overrides (per coverArtId).
    private static let overridesKey = "cassette.dominantColor.overrides"

    // Pure memoization store — not UI state. @ObservationIgnored so a cache write (on a cold-cover miss)
    // never invalidates a view that called dominantColor() during its body. Colors that drive UI flow
    // through observed @State / view-model properties (e.g. FullPlayerViewModel.dominantColor), never this.
    @ObservationIgnored private var cache: [String: Color] = [:]
    /// Bottom-strip (lower 20%) colours — the ARTIST hero only. Keyed by coverArtId but DISTINCT from `cache`, so
    /// one cover can hold both a whole-image dominant (album/player) and a bottom-strip colour (artist) with no
    /// clobber. In-memory only — re-extracted per launch, never mirrored to widgets.
    @ObservationIgnored private var bottomStripCache: [String: Color] = [:]
    /// User-picked colour overrides (per coverArtId), persisted, taking precedence over the extracted dominant.
    /// OBSERVED (unlike `cache`) so themed surfaces re-render the instant the user changes a colour.
    private var colorOverrides: [String: Color] = [:]
    private let ciContext = CIContext(options: [.workingColorSpace: kCFNull as Any])

    init() {
        UserDefaults.standard.removeObject(forKey: Self.legacyUserDefaultsKey)
        let stored = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey) ?? [:]
        var hydrated: [String: Color] = [:]
        hydrated.reserveCapacity(stored.count)
        for (key, value) in stored {
            if let packed = value as? Int {
                hydrated[key] = Self.unpack(packed)
            }
        }
        cache = hydrated

        let storedOverrides = UserDefaults.standard.dictionary(forKey: Self.overridesKey) ?? [:]
        var hydratedOverrides: [String: Color] = [:]
        for (key, value) in storedOverrides {
            if let packed = value as? Int { hydratedOverrides[key] = Self.unpack(packed) }
        }
        colorOverrides = hydratedOverrides
        Logger.dominantColor.debug("Hydrated \(hydrated.count) dominant colors + \(hydratedOverrides.count) overrides.")
    }

    /// Returns the dominant color for the given image, or Color.clear if unavailable.
    /// Checks the in-memory cache (hydrated from UserDefaults at launch) before processing.
    func dominantColor(for coverArtId: String?, image: PlatformImage?) -> Color {
        guard let coverArtId else { return .clear }
        if let override = colorOverrides[coverArtId] { return override }
        if let cached = cache[coverArtId] { return cached }
        guard let image else { return .clear }
        guard let result = extract(from: image) else { return .clear }
        cache[coverArtId] = result.color
        persistColor(result.packed, forKey: coverArtId)
        return result.color
    }

    /// Bottom-strip (lower 20%) average — the ARTIST hero only. An artist photo's whole-image average washes out
    /// to a grey mid-tone; its bottom edge (what melts into the body) is the darker tone the hero needs for a
    /// seamless meet. Override-first like `dominantColor`, cached separately so it can't clobber the whole-image
    /// dominant of the same cover. Pass `image: nil` for a cache-only read (returns .clear if not yet extracted).
    func bottomStripColor(for coverArtId: String?, image: PlatformImage?) -> Color {
        guard let coverArtId else { return .clear }
        if let override = colorOverrides[coverArtId] { return override }
        if let cached = bottomStripCache[coverArtId] { return cached }
        guard let image else { return .clear }
        guard let result = extract(from: image, bottomStrip: true) else { return .clear }
        bottomStripCache[coverArtId] = result.color
        return result.color
    }

    /// Synchronously returns the memoized color for an id, or nil if not yet extracted. No work.
    func cachedColor(for coverArtId: String) -> Color? {
        colorOverrides[coverArtId] ?? cache[coverArtId]
    }

    /// The user-picked colour override for a cover, if any (nil → the extracted dominant is used).
    func colorOverride(for coverArtId: String) -> Color? { colorOverrides[coverArtId] }

    /// Set (or clear) the override for SEVERAL cover ids at once. An album cover and its songs can carry
    /// distinct cover-art ids for the SAME artwork (e.g. "al-…" vs "mf-…" on Navidrome), so the user's pick is
    /// stored under all of them — the full player (keyed on the song's id) then resolves it too. One persist.
    func setColorOverride(_ color: Color?, forIds ids: [String]) {
        let packed = color.flatMap(Self.pack)
        var dict = UserDefaults.standard.dictionary(forKey: Self.overridesKey) ?? [:]
        for id in ids where !id.isEmpty {
            if let color {
                colorOverrides[id] = color
                if let packed { dict[id] = packed }
            } else {
                colorOverrides.removeValue(forKey: id)
                dict.removeValue(forKey: id)
            }
        }
        UserDefaults.standard.set(dict, forKey: Self.overridesKey)
    }

    /// Resolves a SwiftUI Color to a packed 0xRRGGBB int (sRGB) for persistence; nil if it can't be resolved.
    private static func pack(_ color: Color) -> Int? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #elseif canImport(AppKit)
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
        #endif
        return (Int(max(0, min(1, r)) * 255) << 16) | (Int(max(0, min(1, g)) * 255) << 8) | Int(max(0, min(1, b)) * 255)
    }

    /// Stores a packed color produced off-main by `packedAverageColor(from:)` and returns the Color,
    /// so callers that already extracted off the main actor don't repeat the CoreImage work here.
    func storeColor(packed: Int?, for coverArtId: String) -> Color {
        if let cached = cache[coverArtId] { return cached }
        guard let packed else { return .clear }
        let color = Self.unpack(packed)
        cache[coverArtId] = color
        persistColor(packed, forKey: coverArtId)
        return color
    }

    /// Off-main average-color extraction (packed 0xRRGGBB). `nonisolated` so it runs inside `Task.detached`,
    /// keeping the CoreImage decode/average off the main actor. Mirrors `extract(from:)` but uses a local
    /// CIContext (cheap next to the image decode it follows) instead of the MainActor-isolated instance one.
    nonisolated static func packedAverageColor(from image: PlatformImage) -> Int? {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        #elseif canImport(AppKit)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        #endif

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        // Average the WHOLE image — the cover's representative dominant colour (not just its bottom edge).
        let inputExtent = CIVector(
            x: extent.origin.x,
            y: extent.origin.y,
            z: extent.size.width,
            w: extent.size.height
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: inputExtent
        ]),
        let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return (Int(bitmap[0]) << 16) | (Int(bitmap[1]) << 8) | Int(bitmap[2])
    }

    /// Returns all persisted packed 0xRRGGBB colors keyed by coverArtId.
    /// Used by WidgetSyncService to mirror the cache to the App Group shared container.
    func cachedColors() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey)?
            .compactMapValues { $0 as? Int } ?? [:]
    }

    func invalidate(for coverArtId: String?) {
        guard let coverArtId else { return }
        cache.removeValue(forKey: coverArtId)
        removePersistedColor(forKey: coverArtId)
    }

    func clearCache() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }

    // MARK: - Private

    static func unpack(_ packed: Int) -> Color {
        Color(
            red: Double((packed >> 16) & 0xFF) / 255.0,
            green: Double((packed >> 8) & 0xFF) / 255.0,
            blue: Double(packed & 0xFF) / 255.0
        )
    }

    private func persistColor(_ packed: Int, forKey key: String) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey) ?? [:]
        dict[key] = packed
        UserDefaults.standard.set(dict, forKey: Self.userDefaultsKey)
    }

    private func removePersistedColor(forKey key: String) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey) ?? [:]
        dict.removeValue(forKey: key)
        UserDefaults.standard.set(dict, forKey: Self.userDefaultsKey)
    }

    private func extract(from image: PlatformImage, bottomStrip: Bool = false) -> (color: Color, packed: Int)? {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        #elseif canImport(AppKit)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        #endif

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        // Whole image by default (the cover's representative dominant). The ARTIST hero passes bottomStrip=true
        // to average only the lower 20% — CIImage's origin is bottom-left, so y = origin.y is the VISUAL bottom,
        // giving the dark tone that melts seamlessly into the body (a photo's whole average washes out grey).
        let stripHeight = bottomStrip ? max(1, extent.size.height * 0.20) : extent.size.height
        let inputExtent = CIVector(
            x: extent.origin.x,
            y: extent.origin.y,
            z: extent.size.width,
            w: stripHeight
        )

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: inputExtent
        ]),
        let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let packed = (Int(bitmap[0]) << 16) | (Int(bitmap[1]) << 8) | Int(bitmap[2])
        return (color: Self.unpack(packed), packed: packed)
    }
}
