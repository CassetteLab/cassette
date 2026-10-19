// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Cassette

/// Locks the cover-art tiers.
///
/// A 180pt grid cell on a @3x screen needs 540 px. `thumb` once served both grid cells and 44pt
/// rows at 240 px, and that value was requested from the server too — so the blur arrived over
/// the wire and no amount of local work could undo it.
@Suite("Artwork tiers")
struct ArtworkTierTests {

    @Test("A grid cell's tier covers a 180pt cell on a @3x screen")
    func gridTierCoversRealGridCells() {
        let cellPoints = 180.0
        let scale = 3.0
        #expect(Double(ArtworkTier.grid.decodePixels) >= cellPoints * scale)
    }

    @Test("Tiers grow strictly, so the cheapest adequate one is always the lowest")
    func tiersAreOrdered() {
        #expect(ArtworkTier.thumb.decodePixels < ArtworkTier.grid.decodePixels)
        #expect(ArtworkTier.grid.decodePixels < ArtworkTier.hero.decodePixels)
    }

    @Test("Every tier is reachable from allCases")
    func allCasesIsComplete() {
        // Cache invalidation iterates allCases to drop stale copies. A tier missing from it
        // would leave a changed cover showing its old artwork at that size only.
        #expect(Set(ArtworkTier.allCases) == Set([.thumb, .grid, .hero]))
    }

    @Test("A full cache of any one tier stays under the 120 MB budget")
    func budgetHoldsForEveryTier() {
        let limit = 120 * 1024 * 1024
        for tier in ArtworkTier.allCases {
            // The eviction loop keeps the newest entry whatever its size, so the worst case is
            // the budget plus one image. Anything that no longer fits that shape is a regression.
            #expect(tier.approximateBytes <= limit)
        }
    }

    @Test("Byte cost matches four bytes per pixel")
    func costMatchesDecodedSize() {
        for tier in ArtworkTier.allCases {
            #expect(tier.approximateBytes == tier.decodePixels * tier.decodePixels * 4)
        }
    }

    @Test("Larger tiers are listed cheapest first, so a thumb rides a grid and not a hero")
    func largerTiersAreCheapestFirst() {
        #expect(ArtworkTier.thumb.largerTiers == [.grid, .hero])
        #expect(ArtworkTier.grid.largerTiers == [.hero])
    }

    @Test("The largest tier has nothing above it, so a chain of waits cannot cycle")
    func largestTierTerminatesTheChain() {
        #expect(ArtworkTier.hero.largerTiers.isEmpty)
    }

    @Test("A tier never lists itself, which would be a self-wait")
    func noTierListsItself() {
        for tier in ArtworkTier.allCases {
            #expect(!tier.largerTiers.contains(tier))
        }
    }
}

/// Locks the resampling used to serve a small request from a bigger cached image.
///
/// The rule that matters: the result is either exactly the requested size or nothing at all.
/// Returning something smaller than asked is how grid cells went blurry the first time.
@Suite("Artwork downscaling")
struct ArtworkDownscalingTests {

    /// A square image of `side` pixels, built the same way the cache builds its own.
    private func squareImage(side: Int) -> PlatformImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.setFillColor(red: 0.42, green: 0.28, blue: 0.96, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let cgImage = context.makeImage() else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        #endif
    }

    /// Pixel width, not `size`, which is in points on iOS and would hide a scale factor.
    private func pixelWidth(of image: PlatformImage) -> Int? {
        #if canImport(UIKit)
        return image.cgImage?.width
        #else
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width
        #endif
    }

    @Test("A grid image resamples to exactly the thumb size")
    func gridResamplesToThumb() throws {
        let big = try #require(squareImage(side: ArtworkTier.grid.decodePixels))
        let small = try #require(ArtworkImageCache.downscaled(big, maxDimension: ArtworkTier.thumb.decodePixels))
        #expect(pixelWidth(of: small) == ArtworkTier.thumb.decodePixels)
    }

    @Test("A hero image resamples to exactly the grid size")
    func heroResamplesToGrid() throws {
        let big = try #require(squareImage(side: ArtworkTier.hero.decodePixels))
        let small = try #require(ArtworkImageCache.downscaled(big, maxDimension: ArtworkTier.grid.decodePixels))
        #expect(pixelWidth(of: small) == ArtworkTier.grid.decodePixels)
    }

    @Test("An image already at the requested size is refused, so no work is wasted")
    func sameSizeIsRefused() throws {
        let image = try #require(squareImage(side: 240))
        #expect(ArtworkImageCache.downscaled(image, maxDimension: 240) == nil)
    }

    @Test("A smaller image is never upscaled — that is the blur bug")
    func smallerImageIsNeverUpscaled() throws {
        let small = try #require(squareImage(side: 120))
        #expect(ArtworkImageCache.downscaled(small, maxDimension: 1200) == nil)
    }

    @Test("A non-positive target is refused rather than trapping")
    func nonPositiveTargetIsRefused() throws {
        let image = try #require(squareImage(side: 600))
        #expect(ArtworkImageCache.downscaled(image, maxDimension: 0) == nil)
        #expect(ArtworkImageCache.downscaled(image, maxDimension: -10) == nil)
    }
}
