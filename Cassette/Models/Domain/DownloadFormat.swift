// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// User-configurable format for permanently-downloaded (offline) tracks.
///
/// Independent of `CacheFormat`: the sliding-window cache and explicit downloads can
/// carry different quality (e.g. cache MP3 192 to save space, download the original).
/// `.original` asks the server for the untouched file via Subsonic `format=raw`; the
/// other cases force a transcode through the `format` + `maxBitRate` stream params.
nonisolated enum DownloadFormat: String, CaseIterable, Identifiable, Sendable {
    case original
    case mp3_320
    case mp3_192
    case opus_128

    var id: String { rawValue }

    /// The default — the original server file, matching Cassette's pre-picker behaviour.
    static let `default`: DownloadFormat = .original

    /// Display label for the Settings picker.
    /// Localized so the picker follows the app language; the bitrate labels stay as-is
    /// because they read the same in every language.
    var displayName: String {
        switch self {
        case .original:  return String(localized: "Original", comment: "Download format picker: the server's original file, no transcoding")
        case .mp3_320:   return "MP3 320 kbps"
        case .mp3_192:   return "MP3 192 kbps"
        case .opus_128:  return "Opus 128 kbps"
        }
    }

    /// Subsonic `format` query param. `"raw"` means "no transcoding, serve original file".
    var subsonicFormat: String? {
        switch self {
        case .original:  return "raw"
        case .mp3_320:   return "mp3"
        case .mp3_192:   return "mp3"
        case .opus_128:  return "opus"
        }
    }

    /// Subsonic `maxBitRate` query param (kbps). `nil` = no bitrate constraint.
    var subsonicMaxBitRate: Int? {
        switch self {
        case .original:  return nil
        case .mp3_320:   return 320
        case .mp3_192:   return 192
        case .opus_128:  return 128
        }
    }
}
