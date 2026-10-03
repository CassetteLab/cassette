// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import AVFoundation
import AudioToolbox
import SwiftData
@testable import Cassette

@Suite("Opus files — remuxed to CAF so Apple's decoder plays and seeks them")
@MainActor
struct OpusFileTests {

    /// 0.1 s of 440 Hz, `ffmpeg -f lavfi -i sine=frequency=440:duration=0.1 -c:a libopus -b:a 16k -f opus`.
    private static let opusFile = Data(base64Encoded: """
        T2dnUwACAAAAAAAAAAAAAAAAAAAAAAIotXIBE09wdXNIZWFkAQE4AYC7AAAAAABPZ2dTAAAAAAAAAAAAAAAAAAABAAAASZW+VAEu\
        T3B1c1RhZ3MGAAAAZmZtcGVnAQAAABQAAABlbmNvZGVyPUxhdmMgbGlib3B1c09nZ1MABPgTAAAAAAAAAAAAAAIAAAA5wSZ2BkUx\
        LDc0JHiCAbdsfkDmAAAKvpqnvv+2hdcKceDda6DjxsXDMsZkHm5jUjpFDIpTj0QYsIxkq+yYlnlsVFMwVU6C5BbKWUnYxwldWXij\
        P/esmIUDV0wlJ/WKw/WMdoevflpzXcfZ1s5DLQlJr2/POrQt+pViWY6ZIm/p7sN4m6MSUUUArNFV/6eRtPYcGJOKCT1PUU1wVpwE\
        DuchPEkJ0n+JP8X8ocV+A3iboxG0HL+omxd8PsanS1kLdd2vT/Jw1SshsLXNMVag2dks7MR66Y3hHjevaYJ6r6R62qihX5Z4m6Nf\
        dZz8RdC0OAWcMxKhAbuEHU2z0ObjvosK82FS/jwKKgrJUOHKvDNQh42bz4rPBuL6eAXTNfAR540bvgCVUMQ/jWy8FdGF986GPWxk\
        GKVryOeds/+A
        """)!

    /// The Opus header pages intact, every audio byte garbage: sniffs as Opus but holds no packets.
    private static var brokenOpusFile: Data {
        var data = opusFile
        for index in 90..<data.count { data[index] = 0x5A }
        return data
    }

    private func makeCache() throws -> (cache: AudioStreamCache, container: ModelContainer) {
        let container = try ModelContainer.cassette(inMemory: true)
        return (AudioStreamCache(modelContainer: container), container)
    }

    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("opus-\(UUID().uuidString).\(ext)")
    }

    private static func packetCount(of url: URL) throws -> Int64 {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { throw CocoaError(.fileReadCorruptFile) }
        defer { AudioFileClose(file) }
        var count: Int64 = 0
        var size = UInt32(MemoryLayout<Int64>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &size, &count) == noErr else { throw CocoaError(.fileReadCorruptFile) }
        return count
    }

    /// Plants a download record and its file at `serverId/song.<ext>`; returns the service and file URL.
    private func makeDownload(
        base: URL, ext: String, data: Data
    ) throws -> (service: DownloadService, container: ModelContainer, serverId: UUID, url: URL) {
        let container = try ModelContainer.cassette(inMemory: true)
        let service = DownloadService(
            serverService: MockServerService(),
            modelContainer: container,
            toastService: ToastService(),
            cacheSettings: CacheSettings(),
            baseDirectory: base
        )
        let serverId = UUID()
        let path = "\(serverId.uuidString)/song.\(ext)"
        let url = base.appendingPathComponent("downloads").appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        container.mainContext.insert(DownloadedTrack(
            songId: "song", serverId: serverId, filePath: path,
            fileSize: Int64(data.count), mimeType: "audio/ogg", title: "Song", suffix: "flac"
        ))
        try container.mainContext.save()
        return (service, container, serverId, url)
    }

    private func makeBase() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cassette-opus-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Remuxer

    @Test("Remuxing Ogg-Opus yields a CAF with the same packets")
    func remuxKeepsPackets() throws {
        let source = temporaryURL("opus")
        let destination = temporaryURL("caf")
        try Self.opusFile.write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        try OpusRemuxer.remuxToCAF(from: source, to: destination)

        #expect(try Data(contentsOf: destination).prefix(4) == Data("caff".utf8))
        let packets = try Self.packetCount(of: source)
        #expect(packets > 0)
        #expect(try Self.packetCount(of: destination) == packets)
    }

    @Test("A remux that fails before writing leaves whatever was at the destination untouched")
    func remuxFailureLeavesDestinationAlone() throws {
        let source = temporaryURL("opus")
        let destination = temporaryURL("caf")
        try Self.brokenOpusFile.write(to: source)
        try Data("caff".utf8).write(to: destination)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        #expect(throws: OpusRemuxer.RemuxError.self) { try OpusRemuxer.remuxToCAF(from: source, to: destination) }
        #expect(try Data(contentsOf: destination) == Data("caff".utf8))
    }

    @Test("A directory at the destination is kept and no temporary file is left behind")
    func remuxKeepsDirectoryAtDestination() throws {
        let source = temporaryURL("opus")
        let destination = temporaryURL("caf")
        try Self.opusFile.write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: destination.appendingPathComponent("inside"))
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        #expect(throws: OpusRemuxer.RemuxError.self) { try OpusRemuxer.remuxToCAF(from: source, to: destination) }
        #expect(try Data(contentsOf: destination.appendingPathComponent("inside")) == Data("keep".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
        #expect(!leftovers.contains { $0.hasSuffix(".caf.tmp") })
    }

    @Test("Remuxing a file onto itself is refused and keeps the source")
    func remuxRefusesSourceAsDestination() throws {
        let source = temporaryURL("opus")
        try Self.opusFile.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let samePath = source.deletingLastPathComponent().appendingPathComponent(".").appendingPathComponent(source.lastPathComponent)

        #expect(throws: OpusRemuxer.RemuxError.self) { try OpusRemuxer.remuxToCAF(from: source, to: samePath) }
        #expect(try Data(contentsOf: source) == Self.opusFile)
    }

    @Test("The CAF has a fixed 960-frame packet length, so AudioFileStream knows its duration and seeks exactly")
    func cafSeeksExactly() throws {
        let source = temporaryURL("opus")
        let destination = temporaryURL("caf")
        try Self.opusFile.write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try OpusRemuxer.remuxToCAF(from: source, to: destination)
        let caf = try Data(contentsOf: destination)

        // AudioStreaming opens `.caf` with the CAF type hint.
        var stream: AudioFileStreamID?
        let openStatus = AudioFileStreamOpen(nil, { _, _, _, _ in }, { _, _, _, _, _ in }, kAudioFileCAFType, &stream)
        let parser = try #require(stream)
        defer { AudioFileStreamClose(parser) }
        let parseStatus = caf.withUnsafeBytes { AudioFileStreamParseBytes(parser, UInt32(caf.count), $0.baseAddress!, []) }
        #expect(openStatus == noErr)
        #expect(parseStatus == noErr)

        // AudioStreaming derives the duration from frames per packet; 0 leaves it at 0 and blocks seeking.
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        #expect(AudioFileStreamGetProperty(parser, kAudioFileStreamProperty_DataFormat, &size, &format) == noErr)
        #expect(format.mFramesPerPacket == 960)

        var packetCount: UInt64 = 0
        size = UInt32(MemoryLayout<UInt64>.size)
        #expect(AudioFileStreamGetProperty(parser, kAudioFileStreamProperty_AudioDataPacketCount, &size, &packetCount) == noErr)
        #expect(Int64(packetCount) == (try Self.packetCount(of: source)))
        #expect(Double(packetCount) * Double(format.mFramesPerPacket) / 48_000 > 0)

        var byteOffset: Int64 = 0
        var flags = AudioFileStreamSeekFlags()
        #expect(AudioFileStreamSeek(parser, Int64(packetCount / 2), &byteOffset, &flags) == noErr)
        #expect(!flags.contains(.offsetIsEstimated))
        #expect(byteOffset > 0)
    }

    @Test("The CAF decodes to exactly the same samples as the Ogg-Opus source")
    func cafDecodesIdentically() throws {
        let source = temporaryURL("opus")
        let destination = temporaryURL("caf")
        try Self.opusFile.write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try OpusRemuxer.remuxToCAF(from: source, to: destination)

        func samples(_ url: URL) throws -> [Float] {
            let file = try AVAudioFile(forReading: url)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channels = try #require(buffer.floatChannelData)
            return (0..<Int(buffer.format.channelCount)).flatMap { Array(UnsafeBufferPointer(start: channels[$0], count: Int(buffer.frameLength))) }
        }
        let original = try samples(source)
        #expect(original.count == 4800)
        #expect(try samples(destination) == original)
    }

    /// Rewrites the test file's packets into a CAF from Apple's writer with the given frames per packet.
    /// `twoFramePacket` gets TOC frame-count code 1, so its TOC says twice the length its description claims.
    private func writeVariableFrameCAF(frames: [UInt32], twoFramePacket: Int? = nil, to url: URL) throws {
        let source = temporaryURL("opus")
        try Self.opusFile.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        var input: AudioFileID?
        try #require(AudioFileOpenURL(source as CFURL, .readPermission, 0, &input) == noErr)
        let file = try #require(input)
        defer { AudioFileClose(file) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try #require(AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format) == noErr)
        var cookieSize: UInt32 = 0
        try #require(AudioFileGetPropertyInfo(file, kAudioFilePropertyMagicCookieData, &cookieSize, nil) == noErr)
        var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
        try #require(AudioFileGetProperty(file, kAudioFilePropertyMagicCookieData, &cookieSize, &cookie) == noErr)
        var count = UInt32(frames.count)
        var bytes: UInt32 = 65_536
        var buffer = [UInt8](repeating: 0, count: Int(bytes))
        var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: frames.count)
        _ = AudioFileReadPacketData(file, false, &bytes, &descriptions, 0, &count, &buffer)
        try #require(count == UInt32(frames.count))
        for index in descriptions.indices { descriptions[index].mVariableFramesInPacket = frames[index] }
        if let twoFramePacket {
            let toc = Int(descriptions[twoFramePacket].mStartOffset)
            buffer[toc] = buffer[toc] & 0xFC | 0x01
        }

        var output: AudioFileID?
        try #require(AudioFileCreateWithURL(url as CFURL, kAudioFileCAFType, &format, .eraseFile, &output) == noErr)
        let caf = try #require(output)
        #expect(AudioFileSetProperty(caf, kAudioFilePropertyMagicCookieData, cookieSize, cookie) == noErr)
        #expect(AudioFileWritePackets(caf, false, bytes, descriptions, 0, &count, buffer) == noErr)
        #expect(AudioFileClose(caf) == noErr)
    }

    @Test("Opus without one provable packet length is not remuxed and leaves no file", arguments: [
        [480, 1440, 960, 960, 960, 960],    // mixed lengths whose total still divides evenly
        [0, 0, 0, 0, 0, 0],                 // no frame counts, so no valid frames in the packet table
    ] as [[UInt32]])
    func remuxRejectsVariablePacketLength(frames: [UInt32]) throws {
        let source = temporaryURL("caf")
        let destination = temporaryURL("caf")
        try writeVariableFrameCAF(frames: frames, to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        #expect(throws: OpusRemuxer.RemuxError.self) { try OpusRemuxer.remuxToCAF(from: source, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("Opus whose TOC bytes mix packet lengths is not remuxed, even when the packet table averages out")
    func remuxRejectsMixedTOCLengths() throws {
        let source = temporaryURL("caf")
        let destination = temporaryURL("caf")
        // Every description claims 960 frames, but the first packet's TOC says 2 × 20 ms.
        try writeVariableFrameCAF(frames: [960, 960, 960, 960, 960, 960], twoFramePacket: 0, to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        #expect(throws: OpusRemuxer.RemuxError.self) { try OpusRemuxer.remuxToCAF(from: source, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - Cache

    @Test("An Opus payload served as audio/ogg is cached as .caf, Vorbis stays .ogg")
    func cacheStoresOpusAsCAF() async throws {
        let (cache, _) = try makeCache()
        let serverId = UUID()

        let caf = try await cache.store(data: Self.opusFile, forSongId: "opus", serverId: serverId, mimeType: "audio/ogg")
        #expect(caf.pathExtension == "caf")
        #expect(try Self.packetCount(of: caf) > 0)
        #expect(!FileManager.default.fileExists(atPath: caf.deletingPathExtension().appendingPathExtension("opus").path))
        #expect(await cache.cachedURL(forSongId: "opus", serverId: serverId) == caf)

        let vorbis = Data(Array("OggS".utf8) + [UInt8](repeating: 0, count: 22) + [1, 30, 1] + Array("vorbis".utf8) + [UInt8](repeating: 0, count: 23))
        let ogg = try await cache.store(data: vorbis, forSongId: "vorbis", serverId: serverId, mimeType: "audio/ogg")
        #expect(ogg.pathExtension == "ogg")
        #expect(await cache.cachedURL(forSongId: "vorbis", serverId: serverId) == ogg)
        await cache.clearAllForServer(serverId)
    }

    @Test("Opus that cannot be remuxed is cached as .opus and stays playable from the cache")
    func cacheFallsBackToOpus() async throws {
        let (cache, _) = try makeCache()
        let serverId = UUID()

        let url = try await cache.store(data: Self.brokenOpusFile, forSongId: "broken", serverId: serverId, mimeType: "audio/ogg")
        #expect(url.pathExtension == "opus")
        #expect(!FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("caf").path))
        #expect(await cache.cachedURL(forSongId: "broken", serverId: serverId) == url)
        await cache.clearAllForServer(serverId)
    }

    @Test("A cached Opus file stored as .ogg is dropped on lookup")
    func cacheDropsMislabelledOpus() async throws {
        let (cache, container) = try makeCache()
        let serverId = UUID()
        // Learn the cache directory from a real store, then plant a legacy `.ogg` entry beside it.
        let probe = try await cache.store(data: Data([1]), forSongId: "probe", serverId: serverId, mimeType: "audio/mpeg")
        let relativePath = "\(serverId.uuidString)-legacy.ogg"
        let legacy = probe.deletingLastPathComponent().appendingPathComponent(relativePath)
        try Self.opusFile.write(to: legacy)
        container.mainContext.insert(CachedTrack(
            songId: "legacy", serverId: serverId, filePath: relativePath,
            fileSize: Int64(Self.opusFile.count), mimeType: "audio/ogg"
        ))
        try container.mainContext.save()

        #expect(await cache.cachedURL(forSongId: "legacy", serverId: serverId) == nil)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        await cache.clearAllForServer(serverId)
    }

    // MARK: - Downloads

    @Test("A downloaded Opus file stored as .ogg or .opus is remuxed to .caf on lookup", arguments: ["ogg", "opus"])
    func downloadMigratesToCAF(ext: String) async throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let (service, container, serverId, oldURL) = try makeDownload(base: base, ext: ext, data: Self.opusFile)

        let url = try #require(await service.downloadedURL(forSongId: "song", serverId: serverId))
        #expect(url.lastPathComponent == "song.caf")
        #expect(try Self.packetCount(of: url) > 0)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        let record = try #require(try ModelContext(container).fetch(FetchDescriptor<DownloadedTrack>()).first)
        #expect(record.filePath == "\(serverId.uuidString)/song.caf")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        #expect(record.fileSize == size)
        #expect(await service.downloadedURL(forSongId: "song", serverId: serverId) == url)
    }

    @Test("Concurrent lookups of an Opus download share one migration and keep a playable file")
    func downloadConcurrentLookupsKeepFile() async throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let (service, _, serverId, oldURL) = try makeDownload(base: base, ext: "ogg", data: Self.opusFile)

        let results = await withTaskGroup(of: URL?.self) { group in
            for _ in 0..<8 { group.addTask { await service.downloadedURL(forSongId: "song", serverId: serverId) } }
            return await group.reduce(into: [URL?]()) { $0.append($1) }
        }
        let cafURL = oldURL.deletingPathExtension().appendingPathExtension("caf")
        #expect(results == Array(repeating: cafURL, count: 8))
        #expect(try Self.packetCount(of: cafURL) > 0)
        #expect(await service.downloadedURL(forSongId: "song", serverId: serverId) == cafURL)
    }

    @Test("An Opus migration interrupted before the record was saved completes on the next lookup")
    func downloadRecoversInterruptedMigration() async throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let (service, _, serverId, oldURL) = try makeDownload(base: base, ext: "ogg", data: Self.opusFile)
        // A crashed run left a half-written CAF beside the still-referenced `.ogg`.
        try Data("caff".utf8).write(to: oldURL.deletingPathExtension().appendingPathExtension("caf"))

        let url = try #require(await service.downloadedURL(forSongId: "song", serverId: serverId))
        #expect(url.lastPathComponent == "song.caf")
        #expect(try Self.packetCount(of: url) > 0)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
    }

    @Test("An Opus download that cannot be remuxed keeps its file and record; .ogg is not handed out", arguments: ["ogg", "opus"])
    func downloadKeepsFileWhenRemuxFails(ext: String) async throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let (service, container, serverId, oldURL) = try makeDownload(base: base, ext: ext, data: Self.brokenOpusFile)
        let expected: URL? = ext == "opus" ? oldURL : nil

        #expect(await service.downloadedURL(forSongId: "song", serverId: serverId) == expected)
        #expect(await service.downloadedURL(forSongId: "song", serverId: serverId) == expected)
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        #expect(!FileManager.default.fileExists(atPath: oldURL.deletingPathExtension().appendingPathExtension("caf").path))
        let record = try #require(try ModelContext(container).fetch(FetchDescriptor<DownloadedTrack>()).first)
        #expect(record.filePath == "\(serverId.uuidString)/song.\(ext)")
    }
}
