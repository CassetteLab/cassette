// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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
                Text(isPlaying ? "Pause" : "Play")
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

/// Widget container background that stays readable on light covers: the cover's dominant color, with a dark
/// scrim layered on top ONLY when that color is light, so the white widget content keeps contrast. Mirrors
/// the app's `isLightBackground` luminance threshold (BT.601 perceived luminance > 0.6). Dark covers are
/// unchanged (no scrim).
struct WidgetReadableBackground: View {
    let dominantColor: Color

    private var isLightCover: Bool {
        guard let components = dominantColor.cgColor?.components, components.count >= 3 else { return false }
        let luminance = 0.299 * Double(components[0]) + 0.587 * Double(components[1]) + 0.114 * Double(components[2])
        return luminance > 0.6
    }

    var body: some View {
        ZStack {
            dominantColor
            if isLightCover {
                Color.black.opacity(0.6)
            }
        }
    }
}
#endif
