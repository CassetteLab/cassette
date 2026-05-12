// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
@MainActor
@Observable
final class DominantColorExtractor {
    private static let userDefaultsKey = "cassette.dominantColor.cache"

    private var cache: [String: Color] = [:]
    private let ciContext = CIContext(options: [.workingColorSpace: kCFNull as Any])

    init() {
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

    private func extract(from image: PlatformImage) -> (color: Color, packed: Int)? {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        #elseif canImport(AppKit)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        #endif

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
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
