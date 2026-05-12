// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import UIKit

/// Single pinned item tile shared between Medium (4 tiles) and Large (6 tiles) views.
struct PinnedTileView: View {
    let item: SharedPinnedItem
    let image: UIImage?
    var coverSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.15))
                }
            }
            .frame(width: coverSize, height: coverSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(item.title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: coverSize + 10)
        }
    }
}
