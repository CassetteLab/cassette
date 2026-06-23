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
    // v2: the cache now stores BOTTOM-strip averages (not whole-image) — a fresh key so old whole-image colors
    // are dropped and every cover re-extracts with the new method.
    private static let userDefaultsKey = "cassette.dominantColor.cache.v2"
    private static let legacyUserDefaultsKey = "cassette.dominantColor.cache"

    // Pure memoization store — not UI state. @ObservationIgnored so a cache write (on a cold-cover miss)
    // never invalidates a view that called dominantColor() during its body. Colors that drive UI flow
    // through observed @State / view-model properties (e.g. FullPlayerViewModel.dominantColor), never this.
    @ObservationIgnored private var cache: [String: Color] = [:]
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
        Logger.dominantColor.debug("Hydrated \(hydrated.count) dominant colors from UserDefaults.")
    }

    /// Returns the dominant color for the given image, or Color.clear if unavailable.
    /// Checks the in-memory cache (hydrated from UserDefaults at launch) before processing.
    func dominantColor(for coverArtId: String?, image: PlatformImage?) -> Color {
        guard let coverArtId else { return .clear }
        if let cached = cache[coverArtId] { return cached }
        guard let image else { return .clear }
        guard let result = extract(from: image) else { return .clear }
        cache[coverArtId] = result.color
        persistColor(result.packed, forKey: coverArtId)
        return result.color
    }

    /// Synchronously returns the memoized color for an id, or nil if not yet extracted. No work.
    func cachedColor(for coverArtId: String) -> Color? {
        cache[coverArtId]
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
        // Average only the BOTTOM strip of the cover (CIImage origin is bottom-left → origin.y is the visual
        // bottom), not the whole image — so the themed body color matches where the cover MEETS it: a seamless
        // dark/black continuity for a dark-bottomed photo (Apple-Music style), not a muddy whole-image average.
        let stripHeight = max(1, extent.size.height * 0.20)
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

    /// Returns the packed 0xRRGGBB color for a specific coverArtId, or nil if not cached.
    func packedColor(forCoverArtId id: String) -> Int? {
        UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey)?[id] as? Int
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

    private static func unpack(_ packed: Int) -> Color {
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

    private func extract(from image: PlatformImage) -> (color: Color, packed: Int)? {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        #elseif canImport(AppKit)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        #endif

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        // Average only the BOTTOM strip of the cover (CIImage origin is bottom-left → origin.y is the visual
        // bottom), not the whole image — so the themed body color matches where the cover MEETS it: a seamless
        // dark/black continuity for a dark-bottomed photo (Apple-Music style), not a muddy whole-image average.
        let stripHeight = max(1, extent.size.height * 0.20)
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
