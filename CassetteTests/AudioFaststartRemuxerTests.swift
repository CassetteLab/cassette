// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("AudioFaststartRemuxer — detection + skip paths")
struct AudioFaststartRemuxerTests {

    // MARK: - Synthetic ISO-BMFF box builders

    /// 8-byte-header box (UInt32 big-endian size + 4-char type) with a zero payload.
    private func box(_ type: String, payload: Int) -> [UInt8] {
        let size = 8 + payload
        let header: [UInt8] = [
            UInt8((size >> 24) & 0xFF), UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF),
        ] + Array(type.utf8)
        return header + [UInt8](repeating: 0, count: payload)
    }

    /// 64-bit-largesize box: 4-byte size field == 1, then the real size as UInt64 big-endian.
    private func largeBox(_ type: String, payload: Int) -> [UInt8] {
        let total = UInt64(16 + payload)
        let large = (0..<8).map { UInt8((total >> (8 * (7 - UInt64($0)))) & 0xFF) }
        return [0, 0, 0, 1] + Array(type.utf8) + large + [UInt8](repeating: 0, count: payload)
    }

    /// Size==0 box: runs to EOF (only valid as the last box).
    private func toEndBox(_ type: String, payload: Int) -> [UInt8] {
        [0, 0, 0, 0] + Array(type.utf8) + [UInt8](repeating: 0, count: payload)
    }

    private func withTempFile(_ bytes: [UInt8], ext: String, _ body: (URL) async -> Void) async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remux-test-\(UUID().uuidString).\(ext)")
        do { try Data(bytes).write(to: url) } catch { Issue.record("write failed: \(error)"); return }
        defer { try? FileManager.default.removeItem(at: url) }
        await body(url)
    }

    // MARK: - classify (pure)

    @Test("moov before mdat is faststart")
    func moovFirstIsFaststart() {
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp", "moov", "mdat"]) == .faststart)
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp", "free", "moov", "free", "mdat"]) == .faststart)
    }

    @Test("mdat before moov needs remux")
    func mdatFirstNeedsRemux() {
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp", "mdat", "moov"]) == .needsRemux)
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp", "free", "mdat", "moov"]) == .needsRemux)
    }

    @Test("no ftyp is not an MP4")
    func noFtypIsNotMP4() {
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["moov", "mdat"]) == .notMP4)
        #expect(AudioFaststartRemuxer.classify(boxTypes: []) == .notMP4)
    }

    @Test("no moov (or no mdat) is treated as faststart / no-op")
    func missingMoovOrMdatIsFaststart() {
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp", "mdat"]) == .faststart)   // can't help
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp", "moov"]) == .faststart)   // nothing to move
    }

    // MARK: - Output acceptance (pure)
    //
    // The rule that decides whether a fresh export may overwrite the original download.
    // It has to be stricter than classify(): a truncated export is "faststart" to classify
    // (no moov to move) but must never replace a working file.

    @Test("a complete faststart export is accepted")
    func usableOutputAccepted() {
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["ftyp", "moov", "mdat"]))
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["ftyp", "free", "moov", "free", "mdat"]))
    }

    @Test("a truncated export is rejected even though classify calls it faststart")
    func truncatedOutputRejected() {
        // Each of these is .faststart per classify — the exact hole this guard closes.
        #expect(AudioFaststartRemuxer.classify(boxTypes: ["ftyp"]) == .faststart)
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["ftyp"]) == false)
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["ftyp", "moov"]) == false)
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["ftyp", "mdat"]) == false)
    }

    @Test("a non-MP4 file still yields box types — an empty scan means a read failure, not 'not MP4'")
    func nonMP4StillYieldsTypes() async {
        // FLAC magic. The scanner appends a type before validating the box size, so any readable
        // 8 bytes produce an entry. This is what makes "empty" diagnostic of a failed read.
        var flac: [UInt8] = Array("fLaC".utf8) + [0x00, 0x00, 0x00, 0x22]
        flac.append(contentsOf: [UInt8](repeating: 0, count: 64))
        await withTempFile(flac, ext: "flac") { url in
            let types = AudioFaststartRemuxer.topLevelBoxTypes(atPath: url.path)
            #expect(types != nil)
            #expect(types?.isEmpty == false)
            #expect(AudioFaststartRemuxer.classify(boxTypes: types ?? []) == .notMP4)
        }
    }

    @Test("a file too short to hold a header scans as empty rather than unreadable")
    func shortFileScansEmpty() async {
        await withTempFile([0x00, 0x01, 0x02], ext: "bin") { url in
            #expect(AudioFaststartRemuxer.topLevelBoxTypes(atPath: url.path) == [])
        }
    }

    @Test("an output that is still mdat-first, or not an MP4 at all, is rejected")
    func badLayoutOutputRejected() {
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["ftyp", "mdat", "moov"]) == false)
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: ["moov", "mdat"]) == false)
        #expect(AudioFaststartRemuxer.isUsableFaststartOutput(boxTypes: []) == false)
    }

    // MARK: - topLevelBoxTypes(in:) (pure byte parser)

    @Test("in-memory parser reads ordered top-level box types")
    func parsesInMemoryBoxOrder() {
        let faststart = Data(box("ftyp", payload: 8) + box("moov", payload: 16) + box("mdat", payload: 32))
        #expect(AudioFaststartRemuxer.topLevelBoxTypes(in: faststart) == ["ftyp", "moov", "mdat"])

        let needsRemux = Data(box("ftyp", payload: 8) + box("mdat", payload: 64) + box("moov", payload: 16))
        #expect(AudioFaststartRemuxer.topLevelBoxTypes(in: needsRemux) == ["ftyp", "mdat", "moov"])
    }

    @Test("parser handles 64-bit largesize and size==0 (to-EOF) boxes")
    func parsesLargeAndToEndBoxes() {
        let large = Data(box("ftyp", payload: 8) + largeBox("mdat", payload: 40) + box("moov", payload: 8))
        #expect(AudioFaststartRemuxer.topLevelBoxTypes(in: large) == ["ftyp", "mdat", "moov"])
        #expect(AudioFaststartRemuxer.classify(boxTypes: AudioFaststartRemuxer.topLevelBoxTypes(in: large)) == .needsRemux)

        let toEnd = Data(box("ftyp", payload: 8) + box("moov", payload: 8) + toEndBox("mdat", payload: 24))
        #expect(AudioFaststartRemuxer.topLevelBoxTypes(in: toEnd) == ["ftyp", "moov", "mdat"])
    }

    // MARK: - topLevelBoxTypes(atPath:) (file scanner, seeks past mdat)

    @Test("file scanner reads box order from disk and classifies mdat-first as needsRemux")
    func fileScannerRoundTrip() async {
        let bytes = box("ftyp", payload: 8) + box("mdat", payload: 4096) + box("moov", payload: 16)
        await withTempFile(bytes, ext: "m4a") { url in
            let types = AudioFaststartRemuxer.topLevelBoxTypes(atPath: url.path)
            #expect(types == ["ftyp", "mdat", "moov"])
            #expect(AudioFaststartRemuxer.classify(boxTypes: types ?? []) == .needsRemux)
        }
    }

    // MARK: - Content detection (isM4AContainer) + skip paths (no AVFoundation export)

    @Test("isM4AContainer detects an ftyp container regardless of extension")
    func contentDetection() async {
        let mp4 = box("ftyp", payload: 8) + box("mdat", payload: 16) + box("moov", payload: 8)
        // ftyp content saved with a wrong .mp3 extension is still recognised as a container.
        await withTempFile(mp4, ext: "mp3") { url in
            #expect(AudioFaststartRemuxer.isM4AContainer(atPath: url.path) == true)
        }
        // Non-MP4 bytes (a flac signature, no ftyp) are not a container.
        let flac = Array("fLaC".utf8) + [UInt8](repeating: 0, count: 64)
        await withTempFile(flac, ext: "flac") { url in
            #expect(AudioFaststartRemuxer.isM4AContainer(atPath: url.path) == false)
        }
    }

    @Test("non-MP4 content is skipped (no ftyp → not a container)")
    func nonMP4ContentSkipped() async {
        let flac = Array("fLaC".utf8) + [UInt8](repeating: 0, count: 64)
        await withTempFile(flac, ext: "flac") { url in
            let outcome = await AudioFaststartRemuxer().remuxToFaststartIfNeeded(at: url)
            #expect(outcome == .skipped)
        }
    }

    @Test("already-faststart m4a is skipped (no export attempted)")
    func alreadyFaststartSkipped() async {
        let bytes = box("ftyp", payload: 8) + box("moov", payload: 16) + box("mdat", payload: 32)
        await withTempFile(bytes, ext: "m4a") { url in
            let outcome = await AudioFaststartRemuxer().remuxToFaststartIfNeeded(at: url)
            #expect(outcome == .skipped)
        }
    }
}
