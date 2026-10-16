// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// How much of a collection exists on this device.
///
/// The distinction that matters is `partial`: a single downloaded track is not a downloaded
/// album, and treating it as one leaves no way to fetch the rest — which is exactly what the
/// macOS screens did before this type existed.
nonisolated enum LocalCopyState: Equatable, Sendable {
    /// Nothing is downloaded, or there is nothing to download.
    case none
    case partial(downloaded: Int, total: Int)
    case complete

    init(songs: [DisplayableSong]) {
        let total = songs.count
        guard total > 0 else {
            self = .none
            return
        }
        let downloaded = songs.filter(\.isDownloaded).count
        switch downloaded {
        case 0:      self = .none
        case total:  self = .complete
        default:     self = .partial(downloaded: downloaded, total: total)
        }
    }
}
