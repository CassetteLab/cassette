// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AVFoundation
import OSLog

/// Remuxes non-faststart MP4/M4A audio to faststart (the `moov` atom ahead of `mdat`) so the
/// AudioStreaming engine — which cannot open non-faststart M4A (an AudioFileStream limitation) —
/// can play downloaded m4a offline. Lossless: AVAssetExportSession with the PASSTHROUGH preset
/// copies the elementary streams without re-encoding, for both AAC and ALAC. No-op for every
/// non-m4a container and for files already in faststart layout.
nonisolated struct AudioFaststartRemuxer: Sendable {
    enum Outcome: Sendable, Equatable {
        case skipped   // not an m4a, already faststart, or unreadable — file untouched
        case remuxed   // file replaced in place with the faststart output
        case failed    // remux attempted and failed — original left intact
    }

    enum FaststartState: Sendable, Equatable {
        case notMP4
        case faststart
        case needsRemux
    }

    /// Remuxes `fileURL` in place when it is a non-faststart m4a; otherwise leaves it untouched.
    /// On success the file at `fileURL` IS the optimized output (atomic swap); on any failure the
    /// original is left intact. Detection is CONTENT-based (the `ftyp` box via `classify`), not
    /// extension-based — so a mis-served m4a saved/renamed with a wrong extension (e.g. `.mp3`)
    /// is still handled. Any non-MP4 file returns `.skipped`.
    func remuxToFaststartIfNeeded(at fileURL: URL) async -> Outcome {
        guard let boxes = Self.topLevelBoxTypes(atPath: fileURL.path) else { return .skipped }
        switch Self.classify(boxTypes: boxes) {
        case .notMP4, .faststart:
            return .skipped
        case .needsRemux:
            break
        }

        let asset = AVURLAsset(url: fileURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            Logger.download.warning("[REMUX] passthrough preset unavailable for '\(fileURL.lastPathComponent, privacy: .public)' — original kept")
            return .failed
        }
        // Move the moov atom to the front; passthrough never re-encodes (lossless).
        session.shouldOptimizeForNetworkUse = true

        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("faststart-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: tempURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            Logger.download.warning("[REMUX] export failed for '\(fileURL.lastPathComponent, privacy: .public)': \(error, privacy: .public) — original kept")
            return .failed
        }

        let outSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        guard outSize > 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            Logger.download.warning("[REMUX] empty export for '\(fileURL.lastPathComponent, privacy: .public)' — original kept")
            return .failed
        }

        // Verify the OUTPUT before destroying the input. The export can finish without throwing
        // and still leave a file that is not usable audio (partial write, unexpected track
        // layout); a non-zero size alone would let it overwrite a working download, and the
        // caller has no way back — the payload validator ran on the pre-remux bytes.
        // `classify` is deliberately not enough on its own: it reports a container with no
        // `moov` as `.faststart` ("nothing to optimize"), so a truncated export holding only
        // `ftyp` would pass. Require both boxes, in the right order.
        guard let outBoxes = Self.topLevelBoxTypes(atPath: tempURL.path),
              Self.isUsableFaststartOutput(boxTypes: outBoxes) else {
            try? FileManager.default.removeItem(at: tempURL)
            Logger.download.warning("[REMUX] export produced an unusable layout for '\(fileURL.lastPathComponent, privacy: .public)' — original kept")
            return .failed
        }

        do {
            // Atomic replace on the same directory/volume; consumes tempURL on success.
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            Logger.download.warning("[REMUX] atomic swap failed for '\(fileURL.lastPathComponent, privacy: .public)': \(error, privacy: .public) — original kept")
            return .failed
        }

        // replaceItemAt may relocate the item; confirm the audio really landed back on the
        // path the caller will record and play from. If it didn't, say so rather than
        // reporting a success the download record would then describe wrongly.
        let landedSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        guard landedSize > 0 else {
            Logger.download.error("[REMUX] post-swap file missing at '\(fileURL.lastPathComponent, privacy: .public)' — download is broken")
            return .failed
        }

        Logger.download.info("[REMUX] faststart-remuxed '\(fileURL.lastPathComponent, privacy: .public)'")
        return .remuxed
    }

    // MARK: - Pure box-layout logic (no I/O — unit-testable)

    /// Content sniff: true when the file is an ISO-BMFF (MP4/M4A/M4B) container — its top-level
    /// box layout contains an `ftyp` box. Independent of the file extension, so it recognises a
    /// container that was saved or renamed with a wrong extension.
    nonisolated static func isM4AContainer(atPath path: String) -> Bool {
        guard let boxes = topLevelBoxTypes(atPath: path) else { return false }
        return boxes.contains("ftyp")
    }

    /// Classifies an MP4 top-level box layout: requires `ftyp` to be MP4; `.faststart` when
    /// `moov` precedes `mdat` (or there is no `mdat`); `.needsRemux` when `mdat` precedes `moov`.
    /// A container with no `moov` is reported `.faststart` (nothing to optimize / cannot help).
    nonisolated static func classify(boxTypes types: [String]) -> FaststartState {
        guard types.contains("ftyp") else { return .notMP4 }
        guard let moov = types.firstIndex(of: "moov") else { return .faststart }
        if let mdat = types.firstIndex(of: "mdat"), mdat < moov { return .needsRemux }
        return .faststart
    }

    /// Whether a freshly exported file is safe to swap in over the original. Stricter than
    /// `classify`, which reports a container with no `moov` as `.faststart` ("nothing to
    /// optimize") — that verdict is right for an INPUT and wrong for an OUTPUT, where a missing
    /// `moov` or `mdat` means the export is truncated, not optimal. Pure, so the acceptance rule
    /// is unit-testable without running an export.
    nonisolated static func isUsableFaststartOutput(boxTypes types: [String]) -> Bool {
        types.contains("moov") && types.contains("mdat") && classify(boxTypes: types) == .faststart
    }

    /// Parses the ordered top-level box types from an in-memory MP4 prefix. Pure; used by tests.
    nonisolated static func topLevelBoxTypes(in data: Data, limit: Int = 64) -> [String] {
        let bytes = [UInt8](data)
        return scanBoxTypes(total: UInt64(bytes.count), limit: limit) { offset, length in
            let start = Int(offset)
            guard start >= 0, start + length <= bytes.count else { return nil }
            return Array(bytes[start..<start + length])
        }
    }

    /// Parses the ordered top-level box types directly from a file, reading only box HEADERS
    /// (seeks past `mdat` without loading its payload). Returns nil if the file cannot be read.
    nonisolated static func topLevelBoxTypes(atPath path: String, limit: Int = 64) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let total = try? handle.seekToEnd() else { return nil }
        return scanBoxTypes(total: total, limit: limit) { offset, length in
            do { try handle.seek(toOffset: offset) } catch { return nil }
            guard let chunk = try? handle.read(upToCount: length), chunk.count == length else { return nil }
            return [UInt8](chunk)
        }
    }

    /// Walks the ISO-BMFF top-level box chain: each box is an 8-byte header (UInt32 big-endian
    /// size + 4-char type), with size==1 → 64-bit largesize follows, size==0 → box runs to EOF.
    /// Advances by box size so payloads (notably a large `mdat`) are never read.
    private nonisolated static func scanBoxTypes(
        total: UInt64,
        limit: Int,
        read: (_ offset: UInt64, _ length: Int) -> [UInt8]?
    ) -> [String] {
        var types: [String] = []
        var offset: UInt64 = 0
        while offset + 8 <= total, types.count < limit {
            guard let header = read(offset, 8), header.count == 8 else { break }
            var size = UInt64(header[0]) << 24 | UInt64(header[1]) << 16 | UInt64(header[2]) << 8 | UInt64(header[3])
            let type = String(bytes: header[4..<8], encoding: .ascii) ?? "????"
            var headerLength: UInt64 = 8
            if size == 1 {
                guard let large = read(offset + 8, 8), large.count == 8 else { break }
                size = large.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                headerLength = 16
            } else if size == 0 {
                size = total - offset
            }
            types.append(type)
            guard size >= headerLength else { break }
            offset += size
        }
        return types
    }
}
