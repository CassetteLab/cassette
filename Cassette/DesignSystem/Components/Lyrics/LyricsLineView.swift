// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Single lyric line with Apple Music-style tiered blur, opacity, and scale.
/// Distance from `currentIndex` drives how much each visual effect is applied.
struct LyricsLineView: View {
    let value: String
    let index: Int
    let currentIndex: Int?
    let isSynced: Bool
    let isTappable: Bool
    let onTap: () -> Void

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var blurRadius: CGFloat {
        guard isSynced, currentIndex != nil else { return 0 }
        switch distance {
        case 0: return 0
        case 1: return 1.5
        case 2: return 3.5
        default: return 6
        }
    }

    private var opacity: Double {
        guard isSynced, currentIndex != nil else { return 1.0 }
        switch distance {
        case 0: return 1.0
        case 1: return 0.7
        case 2: return 0.4
        default: return 0.25
        }
    }

    private var scale: CGFloat {
        guard isSynced, currentIndex != nil else { return 1.0 }
        return distance == 0 ? 1.0 : 0.94
    }

    var body: some View {
        Text(value)
            .font(.cassetteLyricsLine)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: blurRadius)
            .scaleEffect(scale, anchor: .leading)
            .animation(.smooth(duration: 0.3), value: currentIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
    }
}
