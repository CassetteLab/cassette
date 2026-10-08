// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AudioToolbox

/// Repackages Ogg-Opus into CAF without re-encoding; AudioFileStream seeks CAF exactly, Ogg-Opus only by estimate.
nonisolated enum OpusRemuxer {
    struct RemuxError: Error, Sendable, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "Opus remux failed at \(step) (OSStatus \(status))" }
    }

    /// 10 hours of audio at the shortest Opus frame (2.5 ms).
    static let maxPackets: Int64 = 14_400_000

    /// Writes the Opus packets of `source` into a new CAF at `destination`; on failure no partial CAF is left there.
    /// Sources with more than `maxPackets` packets are rejected.
    static func remuxToCAF(from source: URL, to destination: URL, maxPackets: Int64 = OpusRemuxer.maxPackets) throws {
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {
            throw RemuxError(step: "destination", status: kAudioFileOperationNotSupportedError)
        }
        // Written next to the destination and moved into place, so a failure never touches what is there.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).caf.tmp")
        do {
            try remux(from: source, to: temporary, maxPackets: maxPackets)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
                guard !isDirectory.boolValue else { throw RemuxError(step: "destination", status: kAudioFileOperationNotSupportedError) }
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw RemuxError(step: step, status: status) }
    }

    // The CAF is written by hand: Apple's writer stores Opus with variable packet length, AudioStreaming needs a fixed one to seek.
    private static func remux(from source: URL, to destination: URL, maxPackets: Int64) throws {
        var input: AudioFileID?
        try check(AudioFileOpenURL(source as CFURL, .readPermission, 0, &input), "open")
        guard let input else { throw RemuxError(step: "open", status: kAudioFileUnspecifiedError) }
        defer { AudioFileClose(input) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioFileGetProperty(input, kAudioFilePropertyDataFormat, &size, &format), "format")
        guard format.mFormatID == kAudioFormatOpus else { throw RemuxError(step: "format", status: kAudioFileUnsupportedDataFormatError) }

        var maxPacketSize: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioFileGetProperty(input, kAudioFilePropertyMaximumPacketSize, &size, &maxPacketSize), "max packet size")
        // An Opus packet is at most 61,440 bytes (RFC 6716); anything larger is a corrupt header.
        guard (1...65_536).contains(maxPacketSize) else { throw RemuxError(step: "max packet size", status: kAudioFileInvalidFileError) }

        // The cookie carries channel mapping and pre-skip; without it the CAF may not decode.
        var cookieSize: UInt32 = 0
        try check(AudioFileGetPropertyInfo(input, kAudioFilePropertyMagicCookieData, &cookieSize, nil), "cookie size")
        guard (1...65_536).contains(cookieSize) else { throw RemuxError(step: "cookie size", status: kAudioFileInvalidFileError) }
        var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
        try check(AudioFileGetProperty(input, kAudioFilePropertyMagicCookieData, &cookieSize, &cookie), "read cookie")

        // Priming and remainder frames keep the duration exact and prove the fixed packet length.
        var packetTable = AudioFilePacketTableInfo()
        size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
        try check(AudioFileGetProperty(input, kAudioFilePropertyPacketTableInfo, &size, &packetTable), "packet table")
        guard packetTable.mNumberValidFrames > 0, packetTable.mPrimingFrames >= 0, packetTable.mRemainderFrames >= 0 else {
            throw RemuxError(step: "packet table", status: kAudioFileInvalidFileError)
        }

        // First pass: packet sizes and frame counts only, so the header can be written before the audio.
        var packetSizes: [UInt8] = []
        var audioBytes: Int64 = 0
        var variableFrames = Set<UInt32>()
        var tocSamples = Set<Int>()
        var seenPackets: Int64 = 0
        let packetCount = try readPackets(input, maxPacketSize: maxPacketSize) { descriptions, buffer in
            for description in descriptions {
                seenPackets += 1
                guard seenPackets <= maxPackets else { throw RemuxError(step: "packet count", status: kAudioFileInvalidFileError) }
                let start = Int(description.mStartOffset)
                tocSamples.insert(samplesAt48kHz(buffer[start..<start + Int(description.mDataByteSize)]) ?? 0)
                guard tocSamples.count == 1 else { throw RemuxError(step: "frames per packet", status: kAudioFileUnsupportedDataFormatError) }
                packetSizes += berEncoded(UInt64(description.mDataByteSize))
                audioBytes += Int64(description.mDataByteSize)
                variableFrames.insert(description.mVariableFramesInPacket)
            }
        }
        guard packetCount > 0 else { throw RemuxError(step: "read packets", status: kAudioFileInvalidFileError) }

        let (withPriming, primingOverflow) = packetTable.mNumberValidFrames.addingReportingOverflow(Int64(packetTable.mPrimingFrames))
        let (totalFrames, remainderOverflow) = withPriming.addingReportingOverflow(Int64(packetTable.mRemainderFrames))
        let framesPerPacket = totalFrames / packetCount
        // Opus packets last at most 120 ms, i.e. 5760 frames at 48 kHz.
        guard !primingOverflow, !remainderOverflow, totalFrames % packetCount == 0, (1...5760).contains(framesPerPacket),
              variableFrames.isSubset(of: [0, UInt32(framesPerPacket)]),
              // The packet table only gives an average; every TOC byte must agree on the same length.
              tocSamples.count == 1, let samples = tocSamples.first, samples > 0,
              Double(samples) * format.mSampleRate / 48_000 == Double(framesPerPacket) else {
            throw RemuxError(step: "frames per packet", status: kAudioFileUnsupportedDataFormatError)
        }

        var description = withUnsafeBytes(of: format.mSampleRate.bitPattern.bigEndian, Array.init)
        description += bigEndian(format.mFormatID) + bigEndian(format.mFormatFlags) + bigEndian(UInt32(0))
        description += bigEndian(UInt32(framesPerPacket)) + bigEndian(format.mChannelsPerFrame) + bigEndian(UInt32(0))
        var packetChunk = bigEndian(packetCount) + bigEndian(packetTable.mNumberValidFrames)
        packetChunk += bigEndian(packetTable.mPrimingFrames) + bigEndian(packetTable.mRemainderFrames) + packetSizes

        var header = Array("caff".utf8) + bigEndian(UInt16(1)) + bigEndian(UInt16(0))
        header += chunkHeader("desc", Int64(description.count)) + description
        header += chunkHeader("kuki", Int64(cookie.count)) + cookie
        header += chunkHeader("pakt", Int64(packetChunk.count)) + packetChunk
        // The data chunk opens with a 4-byte edit count.
        header += chunkHeader("data", 4 + audioBytes) + bigEndian(UInt32(0))

        guard FileManager.default.createFile(atPath: destination.path, contents: Data(header)) else {
            throw RemuxError(step: "create", status: kAudioFilePermissionsError)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.seekToEnd()

        // Second pass: stream the packet bytes behind the header.
        var writtenBytes: Int64 = 0
        let writtenPackets = try readPackets(input, maxPacketSize: maxPacketSize) { descriptions, buffer in
            var batch = Data()
            for description in descriptions {
                let start = Int(description.mStartOffset)
                batch.append(contentsOf: buffer[start..<start + Int(description.mDataByteSize)])
            }
            try output.write(contentsOf: batch)
            writtenBytes += Int64(batch.count)
        }
        guard writtenPackets == packetCount, writtenBytes == audioBytes else {
            throw RemuxError(step: "write packets", status: kAudioFileInvalidFileError)
        }
        try output.synchronize()
    }

    /// Reads all packets of `input` in batches and hands each batch to `body`; returns the packet count.
    private static func readPackets(
        _ input: AudioFileID, maxPacketSize: UInt32,
        _ body: (ArraySlice<AudioStreamPacketDescription>, [UInt8]) throws -> Void
    ) throws -> Int64 {
        let batch: UInt32 = 256
        var buffer = [UInt8](repeating: 0, count: Int(maxPacketSize) * Int(batch))
        var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: Int(batch))
        var packet: Int64 = 0
        while true {
            var count = batch
            var bytes = UInt32(buffer.count)
            // End of file may come back as an error together with the last packets.
            let status = AudioFileReadPacketData(input, false, &bytes, &descriptions, packet, &count, &buffer)
            guard status == noErr || status == kAudioFileEndOfFileError else { throw RemuxError(step: "read packets", status: status) }
            if count == 0 { break }
            for description in descriptions[0..<Int(count)] where description.mStartOffset < 0 || Int(description.mStartOffset) + Int(description.mDataByteSize) > Int(bytes) {
                throw RemuxError(step: "read packets", status: kAudioFileInvalidPacketOffsetError)
            }
            try body(descriptions[0..<Int(count)], buffer)
            packet += Int64(count)
            if status == kAudioFileEndOfFileError { break }
        }
        return packet
    }

    /// Samples in one Opus packet at 48 kHz from its TOC byte (RFC 6716 §3.1); nil for a malformed packet.
    private static func samplesAt48kHz(_ packet: ArraySlice<UInt8>) -> Int? {
        guard let toc = packet.first else { return nil }
        let config = Int(toc >> 3)
        let frameSamples: Int
        switch config {
        case 0..<12: frameSamples = [480, 960, 1920, 2880][config % 4]   // SILK: 10, 20, 40, 60 ms
        case 12..<16: frameSamples = [480, 960][config % 2]              // Hybrid: 10, 20 ms
        default: frameSamples = [120, 240, 480, 960][config % 4]         // CELT: 2.5, 5, 10, 20 ms
        }
        let frames: Int
        switch toc & 0x03 {
        case 0: frames = 1
        case 1, 2: frames = 2
        default:
            guard packet.count >= 2 else { return nil }
            frames = Int(packet[packet.startIndex + 1] & 0x3F)
        }
        let samples = frames * frameSamples
        return (1...5760).contains(samples) ? samples : nil
    }

    private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }

    private static func chunkHeader(_ type: String, _ size: Int64) -> [UInt8] {
        Array(type.utf8) + bigEndian(size)
    }

    /// CAF packet table sizes: 7 bits per byte, most significant first, high bit set on all but the last byte.
    private static func berEncoded(_ value: UInt64) -> [UInt8] {
        var bytes = [UInt8(value & 0x7F)]
        var value = value >> 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }
}
