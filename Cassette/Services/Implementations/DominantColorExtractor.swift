// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import CoreImage

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Extracts the dominant (average) color from a cover art image using CIAreaAverage.
/// Results are cached in memory keyed by coverArtId so each image is processed at most once.
@MainActor
@Observable
final class DominantColorExtractor {
    private var cache: [String: Color] = [:]
    private let ciContext = CIContext(options: [.workingColorSpace: kCFNull as Any])

    /// Returns the dominant color for the given image, or Color.clear if unavailable.
    /// Uses the cache if the coverArtId has been seen before.
    func dominantColor(for coverArtId: String?, image: PlatformImage?) -> Color {
        guard let coverArtId else { return .clear }
        if let cached = cache[coverArtId] { return cached }
        guard let image else { return .clear }
        let color = extract(from: image)
        cache[coverArtId] = color
        return color
    }

    func clearCache() {
        cache.removeAll()
    }

    private func extract(from image: PlatformImage) -> Color {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return .clear }
        #elseif canImport(AppKit)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return .clear }
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
        let outputImage = filter.outputImage else { return .clear }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return Color(
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )
    }
}
