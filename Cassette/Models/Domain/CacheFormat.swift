// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// User-configurable format for cached tracks. Exposed in Settings (phase 5).
/// `.matchStream` caches the same format the server serves for streaming.
/// Other cases force a specific transcode via Subsonic `format` + `maxBitRate` params.
nonisolated enum CacheFormat: String, CaseIterable, Identifiable, Sendable {
    case matchStream
    case flacOriginal
    case mp3_320
    case mp3_192
    case opus_128

    var id: String { rawValue }

    /// Display label for Settings UI.
    /// Localized so the picker follows the app language; the codec/bitrate labels stay as-is
    /// because they read the same in every language.
    var displayName: String {
        switch self {
        case .matchStream:  return String(localized: "Match stream format", comment: "Cache format picker: cache the same format the server streams")
        case .flacOriginal: return "FLAC"
        case .mp3_320:      return "MP3 320 kbps"
        case .mp3_192:      return "MP3 192 kbps"
        case .opus_128:     return "Opus 128 kbps"
        }
    }

    /// Subsonic `format` query param. `nil` = no format override (server default).
    var subsonicFormat: String? {
        switch self {
        case .matchStream:  return nil
        case .flacOriginal: return "raw"  // Subsonic "raw" = no transcoding, serve original file
        case .mp3_320:      return "mp3"
        case .mp3_192:      return "mp3"
        case .opus_128:     return "opus"
        }
    }

    /// Subsonic `maxBitRate` query param (kbps). `nil` = no bitrate constraint.
    var subsonicMaxBitRate: Int? {
        switch self {
        case .matchStream, .flacOriginal: return nil
        case .mp3_320:                    return 320
        case .mp3_192:                    return 192
        case .opus_128:                   return 128
        }
    }
}
