// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("AudioContainer — magic-byte sniffing")
struct AudioContainerSnifferTests {

    private func bytes(_ ascii: String, padTo length: Int = 16) -> [UInt8] {
        var out = Array(ascii.utf8)
        if out.count < length { out += [UInt8](repeating: 0, count: length - out.count) }
        return out
    }

    @Test("FLAC bytes are recognised even when the server calls them m4a")
    func flacIsFlac() {
        // The observed failure: Navidrome declared suffix "m4a" and sent this.
        #expect(AudioContainer.sniff(magic: bytes("fLaC")) == .flac)
    }

    @Test("an ISO-BMFF container is recognised from ftyp at offset 4")
    func mp4IsMP4() {
        let mp4: [UInt8] = [0x00, 0x00, 0x00, 0x20] + Array("ftypM4A ".utf8)
        #expect(AudioContainer.sniff(magic: mp4) == .mp4)
    }

    @Test("mp3 is recognised from an ID3 tag or a bare frame sync")
    func mp3IsMP3() {
        #expect(AudioContainer.sniff(magic: bytes("ID3")) == .mp3)
        #expect(AudioContainer.sniff(magic: [0xFF, 0xFB, 0x90, 0x00]) == .mp3)
        #expect(AudioContainer.sniff(magic: [0xFF, 0xF1, 0x00, 0x00]) == .mp3)
    }

    @Test("ogg, wav and aiff are recognised")
    func otherContainers() {
        #expect(AudioContainer.sniff(magic: bytes("OggS")) == .ogg)
        #expect(AudioContainer.sniff(magic: Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WAVE".utf8)) == .wav)
        #expect(AudioContainer.sniff(magic: Array("FORM".utf8) + [0, 0, 0, 0] + Array("AIFF".utf8)) == .aiff)
        #expect(AudioContainer.sniff(magic: Array("FORM".utf8) + [0, 0, 0, 0] + Array("AIFC".utf8)) == .aiff)
    }

    @Test("RIFF without WAVE, and unknown or truncated bytes, match nothing")
    func unknownBytes() {
        // A RIFF container that is not WAVE must not be claimed.
        #expect(AudioContainer.sniff(magic: Array("RIFF".utf8) + [0, 0, 0, 0] + Array("AVI ".utf8)) == nil)
        #expect(AudioContainer.sniff(magic: bytes("nope")) == nil)
        #expect(AudioContainer.sniff(magic: []) == nil)
        #expect(AudioContainer.sniff(magic: [0xFF]) == nil)   // truncated frame sync
    }

    @Test("sniffing a real file on disk agrees with sniffing its bytes")
    func sniffsFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sniff-\(UUID().uuidString).m4a")   // deliberately mislabelled
        try Data(bytes("fLaC", padTo: 64)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AudioContainer.sniff(atPath: url.path) == .flac)
    }

    @Test("sniffing a missing file yields nil rather than a wrong guess")
    func missingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).m4a").path
        #expect(AudioContainer.sniff(atPath: missing) == nil)
    }
}
