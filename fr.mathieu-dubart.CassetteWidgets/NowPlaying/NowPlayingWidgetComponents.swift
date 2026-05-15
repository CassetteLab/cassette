// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import UIKit
import AppIntents

/// Cover art thumbnail shared between Small and Medium NowPlaying widget views.
/// Caller is responsible for applying `.frame()` before this view.
struct WidgetCoverArtView: View {
    let image: UIImage?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.15))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Interactive play/pause CTA shared between Small and Medium NowPlaying widget views.
struct WidgetPlayButton: View {
    let isPlaying: Bool

    var body: some View {
        Button(intent: PlayPauseIntent()) {
            HStack(spacing: 4) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption)
                Text(isPlaying ? "Pause" : "Lecture")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
