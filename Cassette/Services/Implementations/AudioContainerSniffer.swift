// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// The audio container a downloaded payload actually is, decided from its magic bytes.
///
/// Downloads are named from the server-declared suffix, and a Subsonic server can declare one
/// container while sending another — an `m4a` suffix over FLAC bytes, for instance, when a
/// transcode is configured but not applied. The extension is what the playback engine picks its
/// parser from, so a wrong one makes a perfectly good file unplayable: it is handed to the m4a
/// parser, which finds no `ftyp`, yields nothing, and the track ends instantly at full duration.
///
/// Sniffing the bytes and naming the file after what it IS makes the download independent of the
/// server's metadata being truthful.
nonisolated enum AudioContainer: String, Sendable, CaseIterable {
    case mp4  = "m4a"
    case flac = "flac"
    case mp3  = "mp3"
    case ogg  = "ogg"
    case wav  = "wav"
    case aiff = "aiff"

    /// Bytes needed to recognise every container below (`FORM`/`RIFF` need the type at offset 8).
    static let magicPrefixLength = 12

    /// Identifies the container from a file prefix, or nil when it matches nothing known.
    /// Pure, so the byte patterns are unit-testable without touching the disk.
    static func sniff(magic bytes: [UInt8]) -> AudioContainer? {
        func matches(_ ascii: String, at offset: Int) -> Bool {
            let pattern = Array(ascii.utf8)
            guard bytes.count >= offset + pattern.count else { return false }
            return Array(bytes[offset..<offset + pattern.count]) == pattern
        }

        if matches("fLaC", at: 0) { return .flac }
        if matches("OggS", at: 0) { return .ogg }
        if matches("RIFF", at: 0), matches("WAVE", at: 8) { return .wav }
        if matches("FORM", at: 0), matches("AIFF", at: 8) || matches("AIFC", at: 8) { return .aiff }
        // ISO-BMFF: the `ftyp` box type sits after the 4-byte box size.
        if matches("ftyp", at: 4) { return .mp4 }
        if matches("ID3", at: 0) { return .mp3 }
        // Bare MPEG audio frame sync: 11 set bits.
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 { return .mp3 }
        return nil
    }

    /// Identifies the container of a file on disk, reading only its first bytes.
    static func sniff(atPath path: String) -> AudioContainer? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: magicPrefixLength), !prefix.isEmpty else { return nil }
        return sniff(magic: [UInt8](prefix))
    }
}
