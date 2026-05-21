// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// A single contiguous downloaded byte range.
nonisolated struct ByteRange: Sendable {
    let offset: Int64
    var data: Data

    var endOffset: Int64 { offset + Int64(data.count) }
}

/// In-memory store for downloaded byte ranges of a single audio stream.
/// All stored ranges are kept sorted, non-overlapping, and coalesced.
/// No file I/O — pure memory. CacheService integration happens in Phase 4.
actor ChunkStore {
    private var ranges: [ByteRange] = []
    private(set) var totalLength: Int64?

    func setTotalLength(_ length: Int64) {
        totalLength = length
    }

    /// Inserts data at the given absolute offset, coalescing with any adjacent
    /// or overlapping existing ranges.
    func store(data: Data, at offset: Int64) {
        let incoming = ByteRange(offset: offset, data: data)
        var combined = incoming
        var survivors: [ByteRange] = []

        for existing in ranges {
            let noOverlap = existing.endOffset < combined.offset || existing.offset > combined.endOffset
            if noOverlap {
                survivors.append(existing)
            } else {
                let mergedOffset = min(existing.offset, combined.offset)
                let mergedEnd   = max(existing.endOffset, combined.endOffset)
                var merged = Data(count: Int(mergedEnd - mergedOffset))

                let existingStart = Int(existing.offset - mergedOffset)
                merged.replaceSubrange(
                    existingStart ..< existingStart + existing.data.count,
                    with: existing.data
                )

                let combinedStart = Int(combined.offset - mergedOffset)
                merged.replaceSubrange(
                    combinedStart ..< combinedStart + combined.data.count,
                    with: combined.data
                )

                combined = ByteRange(offset: mergedOffset, data: merged)
            }
        }

        survivors.append(combined)
        ranges = survivors.sorted { $0.offset < $1.offset }
    }

    /// Returns the bytes for the requested range if fully covered; nil otherwise.
    func data(for range: Range<Int64>) -> Data? {
        for stored in ranges where stored.offset <= range.lowerBound && stored.endOffset >= range.upperBound {
            let start = Int(range.lowerBound - stored.offset)
            let end   = Int(range.upperBound - stored.offset)
            return stored.data.subdata(in: start ..< end)
        }
        return nil
    }

    /// Returns the largest contiguous block of data starting at `offset`, clamped to `limit`.
    /// Returns nil when no stored range covers `offset`.
    func largestContiguousData(from offset: Int64, upTo limit: Int64) -> Data? {
        guard let range = ranges.first(where: { $0.offset <= offset && $0.endOffset > offset }) else {
            return nil
        }
        let dataStart = Int(offset - range.offset)
        let clampedEnd = min(range.endOffset, limit)
        let dataEnd = Int(clampedEnd - range.offset)
        guard dataEnd > dataStart else { return nil }
        return range.data[dataStart ..< dataEnd]
    }

    /// True when a single stored range covers [0, totalLength).
    func isFully(covering totalLength: Int64) -> Bool {
        guard let first = ranges.first else { return false }
        return first.offset == 0 && first.endOffset >= totalLength
    }
}
