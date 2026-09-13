// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftData
import SwiftUI

/// Overall progress of a batch download, shown under a header's action row while the batch runs.
///
/// Counts against `DownloadedTrack` through its own `@Query`, so it advances as files land
/// rather than waiting for the batch to report back. Extracted from the playlist detail view,
/// which is where this shape started; the library and favourites lists show the same thing and
/// there is no reason for three copies of it.
struct DownloadProgressView: View {
    let songs: [DisplayableSong]
    let total: Int
    let secondaryColor: Color
    var tint: Color = .cassetteAccent

    @Query private var downloadedTracks: [DownloadedTrack]

    init(
        songs: [DisplayableSong],
        total: Int,
        serverId: UUID,
        secondaryColor: Color,
        tint: Color = .cassetteAccent
    ) {
        self.songs = songs
        self.total = total
        self.secondaryColor = secondaryColor
        self.tint = tint
        let sid = serverId
        _downloadedTracks = Query(filter: #Predicate<DownloadedTrack> { $0.serverId == sid })
    }

    private var downloaded: Int {
        let downloadedIds = Set(downloadedTracks.map(\.songId))
        return songs.filter { downloadedIds.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: CassetteSpacing.xs) {
            if downloaded == 0 {
                HStack(spacing: CassetteSpacing.s) {
                    ProgressView().scaleEffect(0.8)
                    Text("Starting download…")
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor)
                }
            } else {
                ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(maxWidth: 280)
                Text("Downloading \(downloaded)/\(total) tracks")
                    .font(.cassetteCaption)
                    .foregroundStyle(secondaryColor)
            }
        }
        .frame(minHeight: 44)
        // One announcement for the pair, so VoiceOver reads the progress instead of a bare bar.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(downloaded == 0
            ? Text("Starting download…")
            : Text("Downloading \(downloaded)/\(total) tracks"))
    }
}
